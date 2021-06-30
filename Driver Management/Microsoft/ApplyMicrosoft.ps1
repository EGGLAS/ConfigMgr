<# Author: Nicklas Eriksson & Daniel Gråhns
 Date: 2021-06-30
 Purpose: Download Microsoft drivers & apply drivers during OS Deployment or OS Upgrade. 

 Version: 1.0
 Changelog: 1.0 - 2021-02-11 - Nicklas Eriksson -  Script was created. Purpose to replace the old script with purpose to use one script to handle downloading of drivers and install HPIA.

TO-Do
 - Check if we are running the script in WinPE or not so the drivers can be downloaded during Pre-cache.
 - Fallback to latest support OS?
 - Should be able to run script in debug mode.

ApplyHPIA.ps1 -Siteserver "server.domain.local" -OSVersion "20H2"  
ApplyHPIA.ps1 -Siteserver "server.domain.local" -OSVersion "20H2" -DownloadPath "TSCache"
ApplyHPIA.ps1 -Siteserver "server.domain.local" -OSVersion "20H2" -Precache "PreCache"

NOTES 

Credits
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
    [string]$DownloadPath = "TSCache",
    [parameter(Mandatory = $false, HelpMessage = "PreCache True/False")]
	[string]$PreCache,
    [Parameter(Mandatory=$False,HelpMessage='Specify Path to download to, Not in use yet')]
    [string]$PreCacheDownloadPath = "CCMCache"
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


# Set TS settings.
$LogFile = $TSEnvironment.Value("_SMSTSLogPath") + "\ApplyMicrosoft.log" # ApplyHPIA log location 
$Surface = "SURFACE"

$Scriptversion = "1.0"
Log -Message "ApplyMicrosoft is about to start..." -type 1 -Component "HPIA" -LogFile $LogFile
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

log -Message "Attempting to read local computer variables" -Type 1 -Component ApplyMicrosoft -LogFile $LogFile				        
$Manufacturer = "Microsoft"
$ComputerModel = (Get-WmiObject -Class "Win32_ComputerSystem" | Select-Object -ExpandProperty Model).Trim()
$ComputerSKU = Get-WmiObject -Namespace "root\wmi" -Class "MS_SystemInformation" | Select-Object -ExpandProperty SystemSKU

log -Message "Computermodel: $($ComputerModel)" -Type 1 -Component ApplyMicrosoft -LogFile $LogFile				        
log -Message "SKU: $($ComputerSKU)" -Type 1 -Component ApplyMicrosoft -LogFile $LogFile
log -Message "OSVersion: $($OSVersion)" -Type 1 -Component ApplyMicrosoft -LogFile $LogFile				        
log -Message "Done with reading local computer variables" -Type 1 -Component ApplyMicrosoft -LogFile $LogFile				        


# Variables for ConfigMgr Adminservice.
$Filter = "$Manufacturer - $OSversion - " + $ComputerModel + " " + "- $($ComputerSKU)"
$FilterPackages = "/SMS_Package?`$filter=contains(Name,'$($Filter)')"
$AdminServiceURL = "https://{0}/AdminService/wmi" -f $SiteServer
$AdminServiceUri = $AdminServiceURL + $FilterPackages

log -Message "Will use this filter to attempt to get the correct driver package from adminservice: $($Filter)" -Type 1 -Component HPIA -LogFile $LogFile				        

try {
        log -Message "Trying to access adminservice with the following URL: $($AdminServiceUri)" -Type 1 -Component HPIA -LogFile $LogFile				        
        $AdminServiceResponse = Invoke-RestMethod $AdminServiceUri -Method Get -Credential $Credential -ErrorAction Stop
        log -Message "Found the correct driver package from adminservice." -Type 1 -Component HPIA -LogFile $LogFile
        log -Message "Grabbing Name and PackageID from driverpackage" -Type 1 -Component HPIA -LogFile $LogFile				  
        $AllMicrosoftPackage = $AdminServiceResponse.value  | Select-Object Name,PackageID, SourceDate
        $MicrosoftPackage = $AllMicrosoftPackage | Sort-Object Name,PackageID, SourceDate -Descending | Select-Object -First 1
        log -Message "Name: $($MicrosoftPackage.Name)" -Type 1 -Component HPIA -LogFile $LogFile				
        log -Message "PackageID: $($MicrosoftPackage.PackageID)" -Type 1 -Component HPIA -LogFile $LogFile				
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
        $AllMicrosoftPackage = $AdminServiceResponse.value  | Select-Object Name,PackageID, SourceDate
        $MicrosoftPackage = $AllMicrosoftPackage | Sort-Object Name,PackageID, SourceDate -Descending | Select-Object -First 1
        log -Message "Name: $($MicrosoftPackage.Name)" -Type 1 -Component HPIA -LogFile $LogFile				
        log -Message "PackageID: $($MicrosoftPackage.PackageID)" -Type 1 -Component HPIA -LogFile $LogFile				
        if ($MicrosoftPackage.Count -gt "1")
        {
            
        }
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

    
# Setting TS variabels after Admin service has returned correct objects.    
$TSEnvironment.value("OSDDownloadDestinationLocationType") = "$($DownloadPath)"
$TSEnvironment.value("OSDDownloadContinueDownloadOnError") = "1"
$TSEnvironment.value("OSDDownloadDownloadPackages") = "$($MicrosoftPackage.PackageID)"
$TSEnvironment.value("OSDDownloadDestinationVariable") = "$($Surface)"

Log -Message "Setting OSDDownloadDownloadPackages: $($DownloadPath)" -type 1 -LogFile $LogFile -Component HPIA
Log -Message "Setting OSDDownloadContinueDownloadOnError: 1" -type 1 -LogFile $LogFile -Component HPIA
Log -Message "Setting OSDDownloadDownloadPackages: $($MicrosoftPackage.PackageID)" -type 1 -LogFile $LogFile -Component HPIA
Log -Message "Setting OSDDownloadDestinationVariable: $($Surface)" -type 1 -LogFile $LogFile -Component HPIA


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
$ReturnCode = Invoke-Executable -FilePath "OSDDownloadContent.exe"

    # Match on return code
	if ($ReturnCode -eq 0) {
		log -message "Successfully downloaded package content with PackageID: $($MicrosoftPackage.PackageID)" -Type 1 -Component HPIA -LogFile $LogFile
        write-host "Successfully downloaded package content with PackageID: $($MicrosoftPackage.PackageID)" -ForegroundColor green
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
($ContentPath) = $TSEnvironment.Value("surface01") 
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


 if ([string]::IsNullOrEmpty($PreCache))
 {
		try {
			# Expand compressed driver package archive file
            log -message "Starting to decompress driver package: $($MicrosoftPackage.Name)" -Type 1 -Component ConfigMgr -LogFile $LogFile
            log -message "Decompression destination: $($ContentPath)" -Type 1 -Component ConfigMgr -LogFile $LogFile
            $DriverPackage = Get-ChildItem -Path $ContentPath 

			Expand-Archive -Path $DriverPackage.FullName -DestinationPath $ContentPath -Force -ErrorAction Stop
			log -message "Successfully decompressed driver package" -Type 1 -Component ConfigMgr -LogFile $LogFile
		}
		catch [System.Exception] {
            log -message "Failed to decompress driver package. Error message: $($_.Exception.Message) " -Type 3 -Component ConfigMgr -LogFile $LogFile			
			# Throw terminating error
            Throw
		}
					
		try {
			# Remove compressed driver package archive file
			if (Test-Path -Path $DriverPackage.FullName) {
				Remove-Item -Path $DriverPackage.FullName -Force -ErrorAction Stop
			}
		}
		catch [System.Exception] {
            Log -message "Failed to remove compressed driver package after decompression is done. Error message: $($_.Exception.Message) " -Type 3 -Component ConfigMgr -LogFile $LogFile			
			# Throw terminating error
            Throw
			
		}
						
		# Apply drivers recursively
        log -message "Applying Drivers, this will take some time..." -Type 1 -Component ConfigMgr -LogFile $LogFile
		$ApplyDriverInvocation = Invoke-Executable -FilePath "dism.exe" -Arguments "/Image:$($TSEnvironment.Value('OSDTargetSystemDrive'))\ /Add-Driver /Driver:$($ContentPath) /Recurse"
						
		# Validate driver injection
		if ($ApplyDriverInvocation -eq 0) {
			Log -message "Successfully installed drivers recursively in driver package content location using dism.exe" -Type 1 -Component ConfigMgr -LogFile $LogFile
		}
		else {
			Log -message "An error occurred while installing drivers. Continuing with warning code: $($ApplyDriverInvocation). See DISM.log for more details" -Type 3 -Component ConfigMgr -LogFile $LogFile
		}

}

else {
    Log -Message "Script is running as Precache, skipping to install drivers." -Type 2 -Component "HPIA" -logfile $LogFile

}

Log -Message "Microsoft process is now completed and the following package has been installed to the computer: $($MicrosoftPackage.Name)" -Component "HPIA" -Type 1 -logfile $LogFile