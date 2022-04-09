<# Author: Nicklas Eriksson & Daniel GrÃ¥hns
 Purpose: Download HP Drivers and apply HPIA drivers during OS Deployment or OS Upgrade.
 Link to project: https://github.com/EGGLAS/ConfigMgr
 Created: 2021-02-11
 Latest updated: 2022-03-22
 Current Version: 2.0
 Changelog: 1.0 - 2021-02-11 - Nicklas Eriksson -  Script was created. Purpose to replace the old script with purpose to use one script to handle downloading of drivers and install HPIA.
            1.1 - 2021-04-30 - Daniel Grahns - added a "c" that was missing just because I wanted to be in the changelog ;P and some other stuff that was hillarious ("reboob"), popup added on error.
            1.2 - 2021-04-30 - Nicklas Eriksson & Daniel Grahns -Added PreCache function.
            1.3 - 2021-05-04 - Nicklas Eriksson & Daniel Grahns - Fixed Logging and Errorhandling - Fixed parameters and PreCahche (needs to be tested)
            1.4 - 2021-05-05 - Daniel Grahns - Tested Precache. 
            1.5 - 2021-06-14 - Nicklas Eriksson - Bug fix and added more logging. 
            1.6 - 2022-02-15 - Marcus Wahlstam, Advitum AB
                                - Added search for extra Softpaq files and INF drivers (switch: -ExtraFilesCheck) inside folders ExtraINFFiles and ExtraSPFiles in the root of the package
                                - Added -CleanUp switch (removes $env:SystemDrive\HPIA when done)
                                - Added -OSVersion argument to support Windows 11 (only need to specify this if in PreCache mode, otherwise using currently installed OS)
                                - Added -Build argument (former -OSVersion) to specify build number (only needed in PreCache mode)
                                - Removed unused code
                                - Made -Precache argument a switch (only specify "-PreCache", not "-PreCache "True"")
            1.7 - 2022-03-17 - Nicklas Eriksson - Added option to set an custom TS varible to get which package that was download so it can be used to tatto the registry later in your TS.
                                                - Added some more logging and error handling for easier troubleshooting.
            2.0 - 2022-03-22 - Nicklas Eriksson & Daniel Grahns - Updated to the same version as ImportHPIA.ps1                                     
To-Do:
 - Fallback to latest support OS?
 - Should be able to run script in debug mode.
 - Write back to status message?

 How to run the script:
    - ApplyHPIA.ps1 -Siteserver "server.domain.local" -Build "20H2"  
    - ApplyHPIA.ps1 -Siteserver "server.domain.local" -Build "20H2" -DownloadPath "CCMCache" -BIOSPwd "Password.pwd"
    - ApplyHPIA.ps1 -Siteserver "server.domain.local" -Build "21H2" -OSVersion "Win11" -PreCache
    - ApplyHPIA.ps1 -Siteserver "server.domain.local" -Build "21H2" -BIOSPwd "Password.bin" -ExtraFilesCheck -CleanUp
    - ApplyHPIA.ps1 -Siteserver "server.domain.local" -Build "21H2" -BIOSPwd "Password.bin" -CleanUp

Big shoutout and credit to Maurice Dualy and Nikolaj Andersen for their outstanding work with  Modern Driver Management for making this solution possible. 
Some code are borrowed from their awesome solution to making this solution work.

Contact: Grahns.Daniel@outlook.com, erikssonnicklas@hotmail.com
Twitter: Sigge_gooner 
LinkedIn: https://www.linkedin.com/in/danielgrahns/
          https://www.linkedin.com/in/nicklas-sigge-eriksson
Facebook: https://www.facebook.com/daniel.grahns/

You running this script/function means you will not blame the author(s) if this breaks your stuff. This script/function is provided AS IS without warranty of any kind. The entire risk arising out of the use or performance of the sample scripts and documentation remains with you. 
In no event shall author(s) be held liable for any damages whatsoever (including, without limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary loss) arising out of the use of or inability to use the script or documentation. 
Simply put: Use at your own risk.

#>

[CmdletBinding(DefaultParameterSetName = "CCMCache")]
param(
    [Parameter(Mandatory=$True, HelpMessage='Url to ConfigMgr Adminservice')]
    [string]$SiteServer,
    [parameter(Mandatory=$False, HelpMessage = "Specify the name of BIOS password file.")]
	[string]$BIOSPwd,
    [parameter(Mandatory=$False, HelpMessage = "Specify OS version (Win10|Win11)")]
	[string]$OSVersion,
    [parameter(Mandatory=$False, HelpMessage = "Specify Windows Build (21H2)")]
	[string]$Build,
    [Parameter(Mandatory=$False,HelpMessage='Specify Path to download to')]
    [string]$DownloadPath = "CCMCache",
    [parameter(Mandatory = $false, HelpMessage = "PreCache")]
	[switch]$PreCache,
    [Parameter(Mandatory=$False,HelpMessage='Specify Path to download to, Not in use yet')]
    [string]$PreCacheDownloadPath = "CCMCache",
    [parameter(Mandatory = $false, HelpMessage = "Check for extra SP and INF Files in package")]
	[switch]$ExtraFilesCheck,
    [parameter(Mandatory = $false, HelpMessage = "Remove C:\HPIA when done")]
	[switch]$CleanUp
)

function Log {
    Param (
    [Parameter(Mandatory=$false)]
    $Message,
    [Parameter(Mandatory=$false)]
    $ErrorMessage,
    [Parameter(Mandatory=$false)]
    $Component,
    [Parameter(Mandatory=$false)]
    [int]$Type,                                                    
    [Parameter(Mandatory=$true)]
    $LogFile
                             )
    <#
    Type: 1 = Normal, 2 = Warning (yellow), 3 = Error (red)
    #>
    $Time = Get-Date -Format "HH:mm:ss.ffffff"
    $Date = Get-Date -Format "MM-dd-yyyy"
    if ($ErrorMessage -ne $null) {$Type = 3}
    if ($Component -eq $null) {$Component = " "}
    if ($Type -eq $null) {$Type = 1}
    $LogMessage = "<![LOG[$Message $ErrorMessage" + "]LOG]!><time=`"$Time`" date=`"$Date`" component=`"$Component`" context=`"`" type=`"$Type`" thread=`"`" file=`"`">"
    $LogMessage | Out-File -Append -Encoding UTF8 -FilePath $LogFile
}

# Construct TSEnvironment object
try {
    $TSEnvironment = New-Object -ComObject Microsoft.SMS.TSEnvironment -ErrorAction Stop
}
catch [System.Exception] {
    Write-Warning -Message "Unable to construct Microsoft.SMS.TSEnvironment object" ; exit 3
}

# Set script settings.
$Scriptversion = "2.0"
$LogFile = $TSEnvironment.Value("_SMSTSLogPath") + "\ApplyHPIA.log" # ApplyHPIA log location 
$Softpaq = "SOFTPAQ"
$HPIALogFile = $TSEnvironment.Value("_SMSTSLogPath") + "\HPIAInstall" # Log location for HPIA install.


Log -Message "HPIA is about to start..." -type 1 -Component "HPIA" -LogFile $LogFile
Log -Message "Loading script with version: $Scriptversion" -type 1 -Component "HPIA" -LogFile $LogFile


# Attempt to read TSEnvironment variable AdminserviceUser
$AdminserviceUser = $TSEnvironment.Value("AdminserviceUser")
if (-not ([string]::IsNullOrEmpty($AdminserviceUser))) {
               
        Log -Message "Successfully read service account user name from TS environment variable 'Adminserviceuser': ********" -Type 1 -Component "HPIA" -LogFile $LogFile
    }
else {
        Log -Message "Required service account user name could not be determined from TS environment variable 'Adminserviceuser'" -type 3 -Component "HPIA" -LogFile $LogFile
        $Errorcode = "Required service account user name could not be determined from TS environment variable"
        (new-object -ComObject Microsoft.SMS.TsProgressUI).CloseProgressDialog() ; (new-object -ComObject wscript.shell).Popup("$($Errorcode) ",0,'Warning',0x0 + 0x30) ; Exit 0
    }

# Validate correct value have been either set as a TS environment variable or passed as parameter input for service account password used to authenticate against the AdminService

# Attempt to read TSEnvironment variable AdminservicePassword
$Password = $TSEnvironment.Value("AdminservicePassword")
if (-not([string]::IsNullOrEmpty($Password))) 
{
	Log -Message "Successfully read service account password from TS environment variable 'AdminservicePassword': ********" -Component "HPIA" -type 1 -LogFile $LogFile
}
else
{
	Log -message "Required service account password could not be determined from TS environment variable" -Component "HPIA" -type 3 -LogFile $LogFile
    $Errorcode = "Required service account password could not be determined from TS environment variable"
    (New-Object -ComObject Microsoft.SMS.TsProgressUI).CloseProgressDialog() ; (new-object -ComObject wscript.shell).Popup("$($Errorcode) ",0,'Warning',0x0 + 0x30) ; Exit 0

}

        
# Construct PSCredential object for authentication
$EncryptedPassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
$Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList @($AdminserviceUser, $EncryptedPassword)

# Variables for ConfigMgr Adminservice
if ([string]::IsNullOrEmpty($OSVersion))
{
    Log -Message "OSVersion is not specified, getting OSVersion from WMI" -Component "HPIA" -type 1 -LogFile $LogFile
    $WindowsOSCaption = (Get-CimInstance win32_OperatingSystem).Caption
    Log -Message "Current OS Caption: $WindowsOSCaption" -Component "HPIA" -type 1 -LogFile $LogFile
    
    if ($WindowsOSCaption -like "Microsoft Windows 11*")
    {
        Log -Message "Setting OSMajorVersion to Win11" -Component "HPIA" -type 1 -LogFile $LogFile
        $OSMajorVersion = "Win11"
    }
    elseif ($WindowsOSCaption -like "Microsoft Windows 10*")
    {
        Log -Message "Setting OSMajorVersion to Win10" -Component "HPIA" -type 1 -LogFile $LogFile
        $OSMajorVersion = "Win10"
    }
}
else
{
    Log -Message "OSVersion was specified, setting OSMajorVersion to $OSVersion" -Component "HPIA" -type 1 -LogFile $LogFile
    $OSMajorVersion = $OSVersion
}

if ([string]::IsNullOrEmpty($Build))
{
    $WindowsBuild = Get-ItemPropertyValue "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name DisplayVersion
}
else
{
    $WindowsBuild = $Build
}

$Filter = "HPIA-$OSMajorVersion-$WindowsBuild-" + (Get-WmiObject -Class:Win32_ComputerSystem).Model + " " + (Get-WmiObject -Class:Win32_BaseBoard).Product
$FilterPackages = "/SMS_Package?`$filter=contains(Name,'$($Filter)')"
$AdminServiceURL = "https://{0}/AdminService/wmi" -f $SiteServer
$AdminServiceUri = $AdminServiceURL + $FilterPackages

log -Message "Gathering information from the computer:" -Type 1 -Component HPIA -LogFile $LogFile				        
log -Message " - Computermodel: $((Get-WmiObject -Class:Win32_ComputerSystem).Model)" -Type 1 -Component HPIA -LogFile $LogFile				        
log -Message " - Baseboard: $((Get-WmiObject -Class:Win32_BaseBoard).Product)" -Type 1 -Component HPIA -LogFile $LogFile
log -Message " - OSMajorVersion: $($OSMajorVersion)" -Type 1 -Component HPIA -LogFile $LogFile	
log -Message " - WindowsBuild: $($WindowsBuild)" -Type 1 -Component HPIA -LogFile $LogFile			        
log -Message "Will use this filter to attempt to get the correct driver package from adminservice: $($Filter)" -Type 1 -Component HPIA -LogFile $LogFile				        

try {
        log -Message "Trying to access adminservice with the following URL: $($AdminServiceUri)" -Type 1 -Component HPIA -LogFile $LogFile				        
        $AdminServiceResponse = Invoke-RestMethod $AdminServiceUri -Method Get -Credential $Credential -ErrorAction Stop
        log -Message "Found the correct driver package from adminservice:" -Type 1 -Component HPIA -LogFile $LogFile
        log -Message " - Grabbing propertys Name and PackageID from the driverpackage" -Type 1 -Component HPIA -LogFile $LogFile				  
        $HPIAPackage = $AdminServiceResponse.value  | Select-Object Name,PackageID 
        log -Message "  - Name: $($HPIAPackage.Name)" -Type 1 -Component HPIA -LogFile $LogFile				
        log -Message "  - PackageID: $($HPIAPackage.PackageID)" -Type 1 -Component HPIA -LogFile $LogFile				
        }
catch [System.Security.Authentication.AuthenticationException] {
					
	# Attempt to ignore self-signed certificate binding for AdminService
	# Convert encoded base64 string for ignore self-signed certificate validation functionality, certification is genereic and no need for change. 
	$CertificationValidationCallbackEncoded = "DQAKACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAdQBzAGkAbgBnACAAUwB5AHMAdABlAG0AOwANAAoAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAB1AHMAaQBuAGcAIABTAHkAcwB0AGUAbQAuAE4AZQB0ADsADQAKACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAdQBzAGkAbgBnACAAUwB5AHMAdABlAG0ALgBOAGUAdAAuAFMAZQBjAHUAcgBpAHQAeQA7AA0ACgAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgAHUAcwBpAG4AZwAgAFMAeQBzAHQAZQBtAC4AUwBlAGMAdQByAGkAdAB5AC4AQwByAHkAcAB0AG8AZwByAGEAcABoAHkALgBYADUAMAA5AEMAZQByAHQAaQBmAGkAYwBhAHQAZQBzADsADQAKACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAcAB1AGIAbABpAGMAIABjAGwAYQBzAHMAIABTAGUAcgB2AGUAcgBDAGUAcgB0AGkAZgBpAGMAYQB0AGUAVgBhAGwAaQBkAGEAdABpAG8AbgBDAGEAbABsAGIAYQBjAGsADQAKACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAewANAAoAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgAHAAdQBiAGwAaQBjACAAcwB0AGEAdABpAGMAIAB2AG8AaQBkACAASQBnAG4AbwByAGUAKAApAA0ACgAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAewANAAoAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAaQBmACgAUwBlAHIAdgBpAGMAZQBQAG8AaQBuAHQATQBhAG4AYQBnAGUAcgAuAFMAZQByAHYAZQByAEMAZQByAHQAaQBmAGkAYwBhAHQAZQBWAGEAbABpAGQAYQB0AGkAbwBuAEMAYQBsAGwAYgBhAGMAawAgAD0APQBuAHUAbABsACkADQAKACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgAHsADQAKACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAUwBlAHIAdgBpAGMAZQBQAG8AaQBuAHQATQBhAG4AYQBnAGUAcgAuAFMAZQByAHYAZQByAEMAZQByAHQAaQBmAGkAYwBhAHQAZQBWAGEAbABpAGQAYQB0AGkAbwBuAEMAYQBsAGwAYgBhAGMAawAgACsAPQAgAA0ACgAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAZABlAGwAZQBnAGEAdABlAA0ACgAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAKAANAAoAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAATwBiAGoAZQBjAHQAIABvAGIAagAsACAADQAKACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgAFgANQAwADkAQwBlAHIAdABpAGYAaQBjAGEAdABlACAAYwBlAHIAdABpAGYAaQBjAGEAdABlACwAIAANAAoAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAWAA1ADAAOQBDAGgAYQBpAG4AIABjAGgAYQBpAG4ALAAgAA0ACgAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIABTAHMAbABQAG8AbABpAGMAeQBFAHIAcgBvAHIAcwAgAGUAcgByAG8AcgBzAA0ACgAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAKQANAAoAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgAHsADQAKACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgAHIAZQB0AHUAcgBuACAAdAByAHUAZQA7AA0ACgAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAfQA7AA0ACgAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAB9AA0ACgAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAfQANAAoAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAB9AA0ACgAgACAAIAAgACAAIAAgACAA"
	$CertificationValidationCallback = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($CertificationValidationCallbackEncoded))
					
	# Load required type definition to be able to ignore self-signed certificate to circumvent issues with AdminService running with ConfigMgr self-signed certificate binding
	Add-Type -TypeDefinition $CertificationValidationCallback
	[ServerCertificateValidationCallback]::Ignore()
					
	try {
		# Call AdminService endpoint to retrieve package data
        log -Message "Trying to access adminservice with following URL: $($AdminServiceUri)" -Type 1 -Component HPIA -LogFile $LogFile				
        $AdminServiceResponse = Invoke-RestMethod $AdminServiceUri -Method Get -Credential $Credential -ErrorAction Stop 
        $HPIAPackage = $AdminServiceResponse.value  | Select-Object Name,PackageID 
        log -Message "Name: $($HPIAPackage.Name)" -Type 1 -Component HPIA -LogFile $LogFile				
        log -Message "PackageID: $($HPIAPackage.PackageID)" -Type 1 -Component HPIA -LogFile $LogFile				

	}
	catch [System.Exception] {
		# Throw error code
		log -Message "Failed to retrive driver package from ConfigMgr Adminservice for $($Filter)" -Type 3 -Component HPIA -LogFile $LogFile				
        $Errorcode = "Failed to retrive driver package from ConfigMgr Adminservice for $($Filter), please check logfile $LogFile for more information."
        (new-object -ComObject Microsoft.SMS.TsProgressUI).CloseProgressDialog() ; (new-object -ComObject wscript.shell).Popup("$($Errorcode) ",0,'Warning',0x0 + 0x30) ; Exit 0
        Throw
	}
}
catch {
	# Throw error code
		log -Message "Failed to retrive driver package from ConfigMgr Adminservice for $($Filter)." -Type 3 -Component HPIA -LogFile $LogFile				
        $Errorcode = "Failed to retrive driver package from ConfigMgr Adminservice for $($Filter), please check logfile $LogFile for more information."
        (new-object -ComObject Microsoft.SMS.TsProgressUI).CloseProgressDialog() ; (new-object -ComObject wscript.shell).Popup("$($Errorcode) ",0,'Warning',0x0 + 0x30) ; Exit 0
        Throw
}

# Should have a check to see $HPIAPackage.PackageID contain something.
    
# Setting TS variabels after Admin service has returned correct objects.    
$TSEnvironment.value("OSDDownloadDestinationLocationType") = "$($DownloadPath)"
$TSEnvironment.value("OSDDownloadContinueDownloadOnError") = "1"
$TSEnvironment.value("OSDDownloadDownloadPackages") = "$($HPIAPackage.PackageID)"
$TSEnvironment.value("OSDDownloadDestinationVariable") = "$($Softpaq)"

Log -Message "Setting OSDDownloadDownloadPackages: $($DownloadPath)" -type 1 -LogFile $LogFile -Component HPIA
Log -Message "Setting OSDDownloadContinueDownloadOnError: 1" -type 1 -LogFile $LogFile -Component HPIA
Log -Message "Setting OSDDownloadDownloadPackages: $($HPIAPackage.PackageID)" -type 1 -LogFile $LogFile -Component HPIA
Log -Message "Setting OSDDownloadDestinationVariable: $($Softpaq)" -type 1 -LogFile $LogFile -Component HPIA

if (-not [string]::IsNullOrEmpty($CustomTSVariable))
{
    try
    {
        $TSEnvironment.value("$CustomTSVariable") = "$($HPIAPackage.PackageID)"
        Log -Message "Setting ($CustomTSVariable): "$($HPIAPackage.PackageID)"" -type 1 -LogFile $LogFile -Component HPIA

    }
    catch [DivideByZeroException]
    {
    
        Log -Message "Could not set $($CustomTSVariable): $($HPIAPackage.PackageID)" -Type 3 -Component "Error" -LogFile $LogFile
        Log -Message "Error code: $($_.Exception.Message)" -Type 3 -Component "Error" -LogFile $LogFile

    }

}

function Invoke-Executable {
		param(
			[parameter(Mandatory = $true, HelpMessage = "Specify the file name or path of the executable to be invoked, including the extension")]
			[ValidateNotNullOrEmpty()]
			[string]$FilePath,
			
			[parameter(Mandatory = $false, HelpMessage = "Specify arguments that will be passed to the executable")]
			[ValidateNotNull()]
			[string]$Arguments
		)
		
		# Construct a hash-table for default parameter splatting
		$SplatArgs = @{
			FilePath = $FilePath
			NoNewWindow = $true
			Passthru = $true
			ErrorAction = "Stop"
		}
		
		# Add ArgumentList param if present
		if (-not([System.String]::IsNullOrEmpty($Arguments))) {
			$SplatArgs.Add("ArgumentList", $Arguments)
		}
		
		# Invoke executable and wait for process to exit
		try {
			$Invocation = Start-Process @SplatArgs
			$Handle = $Invocation.Handle
			$Invocation.WaitForExit()
		}
		catch [System.Exception] {
			Write-Warning -Message $_.Exception.Message; break
		}
		
		return $Invocation.ExitCode
	}

# Download Drivers with OSDDownloadContent
log -message "Starting package content download process, this might take some time" -Type 1 -Component HPIA -LogFile $LogFile
$ReturnCode = Invoke-Executable -FilePath (Join-Path -Path $env:windir -ChildPath "CCM\OSDDownloadContent.exe")

    # Match on return code
	if ($ReturnCode -eq 0) {
		log -message "Successfully downloaded package content with PackageID: $($HPIAPackage.PackageID)" -Type 1 -Component HPIA -LogFile $LogFile
        write-host "Successfully downloaded package content with PackageID: $($HPIAPackage.PackageID)" -ForegroundColor green
	}
	else {
		log -Message "Failed to download or driver package is missing in ConfigMgr: $($Filter)." -Type 3 -Component HPIA -LogFile $LogFile
				
		# Throw terminating error
        $Errorcode = "Failed to download or driver package is missing in ConfigMgr: $($Filter)."
        write-host "Failed to download or driver package is missing in ConfigMgr: $($Filter)." -ForegroundColor red
        (new-object -ComObject Microsoft.SMS.TsProgressUI).CloseProgressDialog() ; (new-object -ComObject wscript.shell).Popup("$($Errorcode) ",0,'Warning',0x0 + 0x30) ; Exit 0
        Exit 1
	}

# Set Softpaq to Softpaq01 to get an working directory. 
($ContentPath) = $TSEnvironment.Value("softpaq01") 
Log -Message "Setting TS variable Softpaq01: $($ContentPath)" -type 1 -LogFile $LogFile -Component HPIA

log -Message "Starting to reset the task sequence variable that were used to download drivers" -Type 1 -Component HPIA -LogFile $LogFile
$TSEnvironment.Value("OSDDownloadDownloadPackages") = [System.String]::Empty	
$TSEnvironment.Value("OSDDownloadDestinationLocationType") = [System.String]::Empty
$TSEnvironment.Value("OSDDownloadDestinationVariable") = [System.String]::Empty
$TSEnvironment.Value("OSDDownloadDestinationPath") = [System.String]::Empty

log -Message "Setting task sequence variable OSDDownloadDownloadPackages to a blank value" -Type 1 -Component HPIA -LogFile $LogFile
log -Message "Setting task sequence variable OSDDownloadDestinationLocationType to a blank value" -Type 1 -Component HPIA -LogFile $LogFile
log -Message "Setting task sequence variable OSDDownloadDestinationVariable to a blank value" -Type 1 -Component HPIA -LogFile $LogFile
log -message "Setting task sequence variable OSDDownloadDestinationPath to a blank value" -Type 1 -Component HPIA -LogFile $LogFile



 if (-not $PreCache)
 {
    try
    { 
     # Check for BIOS File.
       if ($BIOSPwd -ne "")
       {
            Log -Message "Check if BIOS file exists." -type 1 -Component "HPIA" -LogFile $LogFile  
            $BIOSPwd = Get-childitem -Path $ContentPath -Filter "*.bin"
            $Argument = "/Operation:Analyze /Action:install /Selection:All /OfflineMode:Repository /noninteractive /Debug /SoftpaqDownloadFolder:C:\HPIA /ReportFolder:$($HPIALogFile) /BIOSPwdFile:$($BIOSPwd)"              
            Log -Message "BIOS file found, will start HPIA with following install arguments: $($Argument)." -type 1 -Component "HPIA" -LogFile $LogFile  
          
       }
       else {
            $Argument = "/Operation:Analyze /Action:install /Selection:All /OfflineMode:Repository /noninteractive /Debug /SoftpaqDownloadFolder:C:\HPIA /ReportFolder:$($HPIALogFile)" 
            Log -Message "BIOS file not found, will start HPIA with following install arguments: $($Argument)." -type 1 -Component "HPIA" -LogFile $LogFile  
 
       }

        # Start HPIA Update process 
        Log -Message "Starting HPIA installation." -type 1 -Component "HPIA" -LogFile $LogFile
        $HPIAProcess = Start-Process -Wait -FilePath "HPImageAssistant.exe" -WorkingDirectory "$ContentPath" -ArgumentList "$Argument" -PassThru
        $Handle = $HPIAProcess.Handle # Cache Info $HPIAProcess.Handle
        $HPIAProcess.WaitForExit();
        $HPIAProcess.ExitCode


        If ($HPIAProcess.ExitCode -eq 0)
        {
            
            Log -Message "Installations is completed" -Component "HPIA" -Type 1 -logfile $LogFile
            write-host "Installations is completed With Exit 0" -ForegroundColor Green

        }

        If ($HPIAProcess.ExitCode -eq 3010)
        {
        
            Log -Message "Install Reboot Required, SoftPaq installations are successful, and at least one requires a reboot" -Component "HPIA" -Type 1 -logfile $LogFile

        }
        elseif ($HPIAProcess.ExitCode -eq 256) 
        {
            Log -Message "The analysis returned no recommendation." -Component "HPIA" -Type 2 -logfile $LogFile
            $Errorcode = "The analysis returned no recommendation.."
            (new-object -ComObject Microsoft.SMS.TsProgressUI).CloseProgressDialog() ; (new-object -ComObject wscript.shell).Popup("$($Errorcode) ",0,'Warning',0x0 + 0x30) ; Exit 0
            Exit 256
        }
        elseif ($HPIAProcess.ExitCode -eq 3020) 
        {
            Log -Message "Installed failed n one or more softpaqs, needs second pass. 3020" -Component "HPIA" -Type 2 -logfile $LogFile
        }
        elseif ($HPIAProcess.ExitCode -eq 4096) 
        {
            Log -Message "This platform is not supported!" -Type 3 -Component "HPIA" -Type 3 -logfile $LogFile
            $Errorcode = "This platform is not supported!"
            (new-object -ComObject Microsoft.SMS.TsProgressUI).CloseProgressDialog() ; (new-object -ComObject wscript.shell).Popup("$($Errorcode) ",0,'Warning',0x0 + 0x30) ; Exit 0
            exit 4096
        }
        elseif ($HPIAProcess.ExitCode -eq 16384) {
        
            Log -Message "No matching configuration found on HP.com" -Type 3 -Component "HPIA" -Type 3 -logfile $LogFile
            $Errorcode = "No matching configuration found on HP.com"
            (new-object -ComObject Microsoft.SMS.TsProgressUI).CloseProgressDialog() ; (new-object -ComObject wscript.shell).Popup("$($Errorcode) ",0,'Warning',0x0 + 0x30) ; Exit 0
        }
        Else
        {
            Log -Message "Process exited with code $($HPIAProcess.ExitCode). Expecting 0." -type 1 -Component "HPIA" -LogFile $LogFile
            $Errorcode = "Process exited with code $($HPIAProcess.ExitCode) . Expecting 0." 
        }

        if ($ExtraFilesCheck)
        {
            Log -Message "Checking if there are any extra SP files to install" -Type 1 -Component "HPIA" -LogFile $LogFile
            $ExtraSPFilesPath = Join-Path $ContentPath "ExtraSPFiles"
            if (Test-Path $ExtraSPFilesPath)
            {
                $ExtraSPFiles = Get-ChildItem $ExtraSPFilesPath | where {$_.Name -like "sp*.exe"}
                $ExtraSPFilesCount = $ExtraSPFiles.Count
                if ($ExtraSPFilesCount -gt 0)
                {
                    Log -Message "Found $ExtraSPFilesCount SP files to install" -Type 1 -Component "HPIA" -LogFile $LogFile
                    foreach ($SPFile in $ExtraSPFiles)
                    {
                        try
                        {
                            Log -Message "Installing extra SP file: $($SPFile.Name)" -Type 1 -Component "HPIA" -LogFile $LogFile
                            $SPFilePath = $SPFile.Fullname
                            Invoke-Executable $SPFilePath -Arguments "-s" -ErrorAction Stop
                            Log -Message "Success installing extra SP file: $($SPFile.Name)" -Type 1 -Component "HPIA" -LogFile $LogFile
                        }
                        catch
                        {
                            Log -Message "FAILED installing extra SP file: $($SPFile.Name)" -Type 3 -Component "HPIA" -LogFile $LogFile
                            continue
                        }
                    }
                    Log -Message "Done installing extra SP files" -Type 1 -Component "HPIA" -LogFile $LogFile
                }
                else
                {
                    Log -Message "No extra SP files found in $ExtraSPFilesPath (named sp*.exe)" -Type 1 -Component "HPIA" -LogFile $LogFile
                }
            }
            else
            {
                Log -Message "No folder named ExtraSPFiles found in package root" -Type 1 -Component "HPIA" -LogFile $LogFile
            }
        
            Log -Message "Checking if there are any extra INF files to apply" -Type 1 -Component "HPIA" -LogFile $LogFile
            $ExtraINFFilesPath = Join-Path $ContentPath "ExtraINFFiles"
            if (Test-Path $ExtraINFFilesPath)
            {
                $ExtraINFFiles = Get-ChildItem $ExtraINFFilesPath -Recurse | where {$_.Name -like "*.inf"}
                $ExtraINFFilesCount = $ExtraINFFiles.Count
                if ($ExtraINFFilesCount -gt 0)
                {
                    Log -Message "Found $ExtraINFFilesCount extra INF files to apply, starting pnputil to apply" -Type 1 -Component "HPIA" -LogFile $LogFile
                    Invoke-Executable -FilePath "powershell.exe" -Arguments "pnputil /add-driver $ExtraINFFilesPath /subdirs /install"
                    Log -Message "Done installing extra SP files" -Type 1 -Component "HPIA" -LogFile $LogFile
                }
                else
                {
                    Log -Message "No extra INF files found in $ExtraINFFilesPath (named *.inf, recursive search)" -Type 1 -Component "HPIA" -LogFile $LogFile
                }
            }
            else
            {
                Log -Message "No folder named ExtraINFFiles found in package root" -Type 1 -Component "HPIA" -LogFile $LogFile
            }
        }

        if ($CleanUp)
        {
            Remove-Item -Path "$env:SystemDrive\HPIA" -Recurse -Force -ErrorAction Ignore
        }

    }
    catch 
    {
        Log -Message "Failed to start the HPImageAssistant.exe: $($_.Exception.Message)" -Component "HPIA" -type 3 -Logfile $Logfile
        Exit $($_.Exception.Message)
    }

}

else {
    Log -Message "Script is running as Precache, skipping to install HPIA." -Type 2 -Component "HPIA" -logfile $LogFile

}
Log -Message "HPIA process is now completed and the following package has been installed to the computer: $($HPIAPackage.Name)" -Component "HPIA" -Type 1 -logfile $LogFile
Log -Message "---------------------------------------------------------------------------------------------------------------------------------------------------" -type 1 -Component "HPIA" -LogFile $LogFile
