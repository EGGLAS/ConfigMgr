<# Author: Nicklas Eriksson & Daniel Grahns
 Date: 2021-02-11
 Purpose: Download HP Drivers and apply HPIA drivers during OS Deployment or OS Upgrade.

 Version: 1.5
 Changelog: 1.0 - 2021-02-11 - Nicklas Eriksson -  Script was created. Purpose to replace the old script with purpose to use one script to handle downloading of drivers and install HPIA.
            1.1 - 2021-04-30 - Daniel Grahns - added a "c" that was missing just because I wanted to be in the changelog ;P and some other stuff that was hillarious ("reboob"), popup added on error.
            1.2 - 2021-04-30 - Nicklas Eriksson & Daniel Grahns -Added PreCache function.
            1.3 - 2021-05-04 - Nicklas Eriksson & Daniel Grahns - Fixed Logging and Errorhandling - Fixed parameters and PreCahche (needs to be tested)
            1.4 - 2021-05-05 - Daniel Grahns - Tested Precache. 
            1.5 - 2021-06-14 - Nicklas Eriksson - Bug fix and added some more log entries. 
            1.6 - 2022-03-17 - Nicklas Eriksson - Added option to set an custom TS varible to get which package that was download so it can be used to tatto the registry later in your TS. Added some more logging and error handling.
TO-Do
 - Fallback to latest support OS?
 - Should be able to run script in debug mode.

ApplyHPIA.ps1 -Siteserver "server.domain.local" -OSVersion "20H2"  
ApplyHPIA.ps1 -Siteserver "server.domain.local" -OSVersion "20H2" -DownloadPath "CCMCache" -BIOSPwd "Password.pwd"
ApplyHPIA.ps1 -Siteserver "server.domain.local" -OSVersion "20H2" -Precache "PreCache"

NOTES 
 - Clean-up install files that are creating under C:\HPIA - Add Remove-Item -Path "C:\HPIA" in task sequence if you want to clean-up, seperate step. 

Big shoutout and credit to Maurice Dualy and Nikolaj Andersen for their outstanding work with  Modern Driver Management for making this solution possible. 
Some code are borrowed from their awesome solution to making this solution work.
#>

[CmdletBinding(DefaultParameterSetName = "CCMCache")]
param(
    [Parameter(Mandatory=$True, HelpMessage='Url to ConfigMgr Adminservice')]
    [string]$SiteServer,
    [Parameter(Mandatory=$True, HelpMessage='OS Version')]
    [string]$OSVersion,
    [parameter(Mandatory=$False, HelpMessage = "Specify the name of BIOS password file.")]
	[string]$BIOSPwd,
    [Parameter(Mandatory=$False,HelpMessage='Specify Path to download to')]
    [string]$DownloadPath = "CCMCache",
    [parameter(Mandatory = $false, HelpMessage = "PreCache True/False")]
	[string]$PreCache,
    [Parameter(Mandatory=$False,HelpMessage='Specify Path to download to, Not in use yet')]
    [string]$PreCacheDownloadPath = "CCMCache",
    [Parameter(Mandatory=$False,HelpMessage='Specify Custom TS Variable')]
    [string]$CustomTSVariable
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

$Scriptversion = 1.6
Log -Message "HPIA is about to start..." -type 1 -Component "HPIA" -Component "HPIA" -type 1 -LogFile $LogFile
Log -Message "Loading script with version: $Scriptversion" -Component "HPIA" -type 1 -LogFile $LogFile

# Construct TSEnvironment object
try {
    $TSEnvironment = New-Object -ComObject Microsoft.SMS.TSEnvironment -ErrorAction Stop
}
catch [System.Exception] {
    Log -Message "Unable to construct Microsoft.SMS.TSEnvironment object" -Type 3 -Component "Error" -LogFile $LogFile
    Log -Message "Error code: $($_.Exception.Message)" -Type 3 -Component "Error" -LogFile $LogFile

    Write-Warning -Message "Unable to construct Microsoft.SMS.TSEnvironment object" ; exit 3
}

# Set TS settings.
$LogFile = $TSEnvironment.Value("_SMSTSLogPath") + "\ApplyHPIA.log" # ApplyHPIA log location 
$Softpaq = "SOFTPAQ"
$HPIALogFile = $TSEnvironment.Value("_SMSTSLogPath") + "\HPIAInstall" # Log location for HPIA install.

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
if ([string]::IsNullOrEmpty($Password)) {
			switch ($Script:PSCmdLet.ParameterSetName) {
				"Debug" {
					Log -Message " - Required service account password could not be determined from parameter input" -Component "HPIA" -type 3 -LogFile $LogFile
				}
				default {
					# Attempt to read TSEnvironment variable AdminservicePassword
					$Password = $TSEnvironment.Value("AdminservicePassword")
					if (-not([string]::IsNullOrEmpty($Password))) {
						Log -Message "Successfully read service account password from TS environment variable 'AdminservicePassword': ********" -Component "HPIA" -type 1 -LogFile $LogFile
					}
					else {
						Log -message "Required service account password could not be determined from TS environment variable" -Component "HPIA" -type 3 -LogFile $LogFile
                        $Errorcode = "Required service account password could not be determined from TS environment variable"
                        (new-object -ComObject Microsoft.SMS.TsProgressUI).CloseProgressDialog() ; (new-object -ComObject wscript.shell).Popup("$($Errorcode) ",0,'Warning',0x0 + 0x30) ; Exit 0

					}
				}
			}
		}
else {
	Log -message "Successfully read service account password from parameter input: ********" -Component "HPIA" -type 1 -LogFile $LogFile
}
        
# Construct PSCredential object for authentication
$EncryptedPassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
$Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList @($AdminserviceUser, $EncryptedPassword)

# Variables for ConfigMgr Adminservice.        
#$Filter = "HPIA-20H2-HP ProBook 430 G5 8536" # Only for test purpose. 
$Filter = "HPIA-$OSversion-" + (Get-WmiObject -Class:Win32_ComputerSystem).Model + " " + (Get-WmiObject -Class:Win32_BaseBoard).Product
$FilterPackages = "/SMS_Package?`$filter=contains(Name,'$($Filter)')"
$AdminServiceURL = "https://{0}/AdminService/wmi" -f $SiteServer
$AdminServiceUri = $AdminServiceURL + $FilterPackages

log -Message "Gathering information from the computer:" -Type 1 -Component HPIA -LogFile $LogFile				        
log -Message " - Computermodel: $((Get-WmiObject -Class:Win32_ComputerSystem).Model)" -Type 1 -Component HPIA -LogFile $LogFile				        
log -Message " - Baseboard: $((Get-WmiObject -Class:Win32_BaseBoard).Product)" -Type 1 -Component HPIA -LogFile $LogFile
log -Message " - OSVersion: $($OSVersion)" -Type 1 -Component HPIA -LogFile $LogFile				        
log -Message "Will use this filter to find and download the correct driver package from adminservice: $($Filter)" -Type 1 -Component HPIA -LogFile $LogFile				        

try {
        log -Message "Trying to access adminservice with the following URL: $($AdminServiceUri)" -Type 1 -Component HPIA -LogFile $LogFile				        
        $AdminServiceResponse = Invoke-RestMethod $AdminServiceUri -Method Get -Credential $Credential -ErrorAction Stop
        log -Message "Found the correct driver package from adminservice" -Type 1 -Component HPIA -LogFile $LogFile
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
        log -Message " - Name: $($HPIAPackage.Name)" -Type 1 -Component HPIA -LogFile $LogFile				
        log -Message " - PackageID: $($HPIAPackage.PackageID)" -Type 1 -Component HPIA -LogFile $LogFile				

	}
	catch [System.Exception] {
		# Throw error code
		log -Message "Failed to retrive driver package from ConfigMgr Adminservice for $($Filter)." -Type 3 -Component HPIA -LogFile $LogFile				
        $Errorcode = "Failed to retrive driver package from ConfigMgr Adminservice for $($Filter)."
        (new-object -ComObject Microsoft.SMS.TsProgressUI).CloseProgressDialog() ; (new-object -ComObject wscript.shell).Popup("$($Errorcode) ",0,'Warning',0x0 + 0x30) ; Exit 0
        Throw
	}
}
catch {
	# Throw error code
		log -Message "Failed to retrive driver package from ConfigMgr Adminservice for $($Filter)." -Type 3 -Component HPIA -LogFile $LogFile				
        $Errorcode = "Failed to retrive driver package from ConfigMgr Adminservice for $($Filter)."
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
log -Message "Setting task sequence variable OSDDownloadDownloadPackages to a blank value" -Type 1 -Component HPIA -LogFile $LogFile
$TSEnvironment.Value("OSDDownloadDownloadPackages") = [System.String]::Empty
		
# Set OSDDownloadDestinationLocationType
log -Message "Setting task sequence variable OSDDownloadDestinationLocationType to a blank value" -Type 1 -Component HPIA -LogFile $LogFile
$TSEnvironment.Value("OSDDownloadDestinationLocationType") = [System.String]::Empty
		
# Set OSDDownloadDestinationVariable
log -Message "Setting task sequence variable OSDDownloadDestinationVariable to a blank value" -Type 1 -Component HPIA -LogFile $LogFile
$TSEnvironment.Value("OSDDownloadDestinationVariable") = [System.String]::Empty
		
# Set OSDDownloadDestinationPath
log -message "Setting task sequence variable OSDDownloadDestinationPath to a blank value" -Type 1 -Component HPIA -LogFile $LogFile
$TSEnvironment.Value("OSDDownloadDestinationPath") = [System.String]::Empty

 if ([string]::IsNullOrEmpty($PreCache))
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
    }
    catch 
    {
        Log -Message "Failed to start the HPImageAssistant.exe: $($_.Exception.Message)" -Component "HPIA" -type 3 -Logfile $Logfile
        Exit $($_.Exception.Message)
    }
    
    Log -Message "HPIA process is now completed and the following package has been installed to the computer: $($HPIAPackage.Name)" -Component "HPIA" -Type 1 -logfile $LogFile

}

else {
    Log -Message "Script is running as Precache, skipping to install HPIA." -Type 1 -Component "HPIA" -logfile $LogFile
}
Log -Message "---------------------------------------------------------------------------------------------------------------------------------------------------" -type 1 -Component "HPIA" -LogFile $LogFile


