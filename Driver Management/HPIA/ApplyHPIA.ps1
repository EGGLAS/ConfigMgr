<# Author: Nicklas Eriksson & Daniel Gråhns
 Date: 2021-03-11
 Purpose: Download HP Drivers and apply HPIA drivers during OS Deployment or OS Upgrade.

 Version: 1.0
 Changelog: 1.0 - 2021-02-11 - Nicklas Eriksson -  Script was created. Purpose to use one script to download and install HPIA.
            1.1 - 2021-04-30 - Daniel Gråhns - added a "c" that was missing just because I wanted to be in the changelog ;P and some other stuff that was hillarious ("reboob"), popup added on error.
 TO-Do
 - Fallback to latest support OS?
 - Clean-up install files that are creating under C:\HPIA
 - Setup for precache.

ApplyHPIA.ps1 -Siteserver "server.domain.local" -OSVersion "20H2"  
ApplyHPIA.ps1 -Siteserver "server.domain.local" -OSVersion "20H2" -DownloadPath "CCMCache" -BIOSPwd "Password.pwd"
ApplyHPIA.ps1 -Siteserver "server.domain.local" -OSVersion "20H2" -Precache "PreCache"

Big shoutout and credit to Maurice Dualy and Nikolaj Andersen for their outstanding work for creating Modern Driver Management for making this possible. 
Some code are borrowed from their awesome solution for making this work.
#>

[CmdletBinding(DefaultParameterSetName = "CCMCache")]
param(
    [Parameter(Mandatory=$True, HelpMessage='Url to ConfigMgr Adminservice')]
    [string]$SiteServer,
    [Parameter(Mandatory=$True, HelpMessage='OS Version')]
    [string]$OSVersion,
    [Parameter(Mandatory=$False, ParameterSetName = "CCMCache",HelpMessage='Specify Path to download to')]
    [string]$DownloadPath = "CCMCache",
    [parameter(Mandatory = $false, ParameterSetName = "PreCache", HelpMessage = "Specify a custom path for the PreCache directory, overriding the default CCMCache directory.")]
	[ValidateNotNullOrEmpty()]
	[string]$PreCache,
    [parameter(Mandatory = $false, ParameterSetName = "BIOSPassword", HelpMessage = "Specify the name of BIOS password file.")]
	[ValidateNotNullOrEmpty()]
	[string]$BIOSPwd
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
$LogFile = $TSEnvironment.Value("_SMSTSLogPath") + "\ApplyHPIA.log"
$Softpaq = "SOFTPAQ"
$HPIALogFile = $TSEnvironment.Value("_SMSTSLogPath") + "\InstallHPIA.log"

# Attempt to read TSEnvironment variable AdminserviceUser
$AdminserviceUser = $TSEnvironment.Value("AdminserviceUser")
if (-not ([string]::IsNullOrEmpty($AdminserviceUser))) {
               
        Log -Message "Successfully read service account user name from TS environment variable 'Adminserviceuser': $($AdminserviceUser)" -Type 1 -Component "HPIA" -LogFile $LogFile
    }
else {
        Log -Message "Required service account user name could not be determined from TS environment variable" -type 3 -Component "HPIA" -LogFile $LogFile
        
        # Throw terminating error
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
						Log -Message "Successfully read service account password from TS environment variable 'AdminservicePassword': ********" -Component "HPIA" -type 3 -LogFile $LogFile
					}
					else {
						Log -message "Required service account password could not be determined from TS environment variable" -Component "HPIA" -type 3 -LogFile $LogFile
						
						# Throw terminating error
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
       
#$Filter = "HPIA-$OSVersion-HP ProBook 430 G6 8536"
$Filter = "HPIA-$OSversion-" + (Get-WmiObject -Class:Win32_ComputerSystem).Model + " " + (Get-WmiObject -Class:Win32_BaseBoard).Product


$FilterPackages = "/SMS_Package?`$filter=contains(Name,'$($Filter)')"
$AdminServiceURL = "https://{0}/AdminService/wmi" -f $SiteServer
$AdminServiceUri = $AdminServiceURL + $FilterPackages

try {
        $AdminServiceResponse = Invoke-RestMethod $AdminServiceUri -Method Get -Credential $Credential -ErrorAction Stop  
        $HPIAPackage = $AdminServiceResponse.value  | Select-Object Name,PackageID 
        
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
        $HPIAPackage = $AdminServiceResponse.value  | Select-Object Name,PackageID 
        
	}
	catch [System.Exception] {
		# Throw terminating error
		log -Message "Failed to retrive driver package from ConfigMgr Adminservice for $($Filter)." -Type 3 -Component HPIA -LogFile $LogFile				
		# Throw terminating error
        $Errorcode = "Failed to retrive driver package from ConfigMgr Adminservice for $($Filter)."
        [System.Windows.MessageBox]::Show("$Errorcode", 'Error','OK','Stop')
	}
}
catch {
	# Throw terminating error
		log -Message "Failed to retrive driver package from ConfigMgr Adminservice for $($Filter)." -Type 3 -Component HPIA -LogFile $LogFile				
		# Throw terminating error
        $Errorcode = "Failed to retrive driver package from ConfigMgr Adminservice for $($Filter)."
        [System.Windows.MessageBox]::Show("$Errorcode", 'Error','OK','Stop')

}

# Should have a check to see $HPIAPackage.PackageID contain something.
    
# Setting TS variabels after Admin service has returned correct objects.    
$TSEnvironment.value("OSDDownloadDestinationLocationType") = "$($DownloadPath)"
$TSEnvironment.value("OSDDownloadContinueDownloadOnError") = "1"
$TSEnvironment.value("OSDDownloadDownloadPackages") = "$($HPIAPackage.PackageID)"
$TSEnvironment.value("OSDDownloadDestinationVariable") = "$($Softpaq)"
$ContentPath = $TSEnvironment.Value("softpaq01") 
Log -Message "Setting OSDDownloadDownloadPackages: $($DownloadPath)" -type 1 -LogFile $LogFile
Log -Message "Setting OSDDownloadContinueDownloadOnError: 1" -type 1 -LogFile $LogFile
Log -Message "Setting OSDDownloadDownloadPackages: $($ContentPath)" -type 1 -LogFile $LogFile
Log -Message "Setting OSDDownloadDestinationVariable: $($Softpaq)" -type 1 -LogFile $LogFile

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

# Download Drivers
log -message " - Starting package content download process, this might take some time" -Type 1 -Component HPIA -LogFile $LogFile
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
        [System.Windows.MessageBox]::Show("$Errorcode", 'Error','OK','Stop')

	}

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

 if ($PreCache -ne "Precache")
 {
    try
    {
     # Check for BIOS File.
       if ($BIOSPwd -eq "")
       {
        LOg -Message "Check if BIOS file exists." -type 1 -Component "HPIA" -LogFile $LogFile  
        $BIOSPwd = Get-childitem -Path C:\Temp\HPIA -Filter "*.pwd"      
       }

        # Start HPIA Update process 
        Log -Message "Starting HPIA installation." -type 1 -Component "HPIA" -LogFile $LogFile
        $HPIAProcess = Start-Process -FilePath "HPImageAssistant.exe" -WorkingDirectory "$ContentPath" -ArgumentList "/Operation:Analyze /Action:install /Selection:All /OfflineMode:Repository /noninteractive /Debug  /SoftpaqDownloadFolder:C:\HPIA /ReportFolder:$($HPIALogFile) /BIOSPwdFile:$($BIOSPwd.Name)" 

    If ($HPIAProcess.ExitCode -eq 0)
    {
        
        Log -Message "Installations is completed" -Component "HPIA" -Type 1 -logfile $LogFile

    }
        If ($HPIAProcess.ExitCode -eq 3010)
    {
        
        Log -Message "Install Reboot Required — SoftPaq installations are successful, and at least one requires a reboobt" -Component "HPIA" -Type 1 -logfile $LogFile

    }
    elseif ($HPIAProcess.ExitCode -eq 256) 
    {
        Log -Message "The analysis returned no recommendation." -Component "HPIA" -Type 2 -logfile $LogFile
        $Errorcode = "The analysis returned no recommendation.."
        [System.Windows.MessageBox]::Show("$Errorcode", 'Error','OK','Stop')
        Exit 256
    }
    elseif ($HPIAProcess.ExitCode -eq 4096) 
    {
        Log -Message "This platform is not supported!" -Type 3 -Component "HPIA" -Type 3 -logfile $LogFile
        $Errorcode = "This platform is not supported!"
        [System.Windows.MessageBox]::Show("$Errorcode", 'Error','OK','Stop')
        exit 4096
    }
    elseif ($HPIAProcess.ExitCode -eq 16384) {
        
        Log -Message "No matching configuration found on HP.com" -Type 3 -Component "HPIA" -Type 3 -logfile $LogFile
        $Errorcode = "No matching configuration found on HP.com"
        [System.Windows.MessageBox]::Show("$Errorcode", 'Error','OK','Stop')
    }
    Else
    {
        Log -Message "Process exited with code $($HPIAProcess.ExitCode). Expecting 0." -Component "HPIA" -Log 3
        $Errorcode = "Process exited with code $($HPIAProcess.ExitCode). Expecting 0."
        [System.Windows.MessageBox]::Show("$Errorcode", 'Error','OK','Stop')

        Exit 
    }
}
catch 
{
    Log -Message "Failed to start the HPImageAssistant.exe: $($_.Exception.Message)" -Component "HPIA" -Log 3
    Exit $($_.Exception.Message)
}

  }
  else
  {
      Log -Message "Script is running as Precache, skipping to install HPIA." -Type 3 -Component "HPIA" -Type 3 -logfile $LogFile

  }

Log -Message "HPIA script is now completed." -Type 3 -Component "HPIA" -Type 3 -logfile $LogFile
