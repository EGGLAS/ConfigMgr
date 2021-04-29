<# Author: Nicklas Eriksson
 Date: 2021-03-11
 Purpose: Download HP Drivers and apply HPIA drivers during OS Deployment.

 Version: 1.0
 Changelog: 1.0 - 2021-02-11 - Nicklas Eriksson -  Script was created. Purpose to use one script to download and install HPIA.

 TO-Do
 - Fallback to latest support OS?
 - Clean-up install files that are creating under C:\HPIA

ApplyHPIA.ps1 -OSVersion 20H2 -Siteserver "server.domain.local" -DownloadPath CCMCache -BIOSPwd "Password.bin"
#>

[CmdletBinding(DefaultParameterSetName = "CCMCahe")]
param(
    [Parameter(Mandatory=$True, HelpMessage='Url to ConfigMgr Adminservice')]
    [string]$SiteServer,
    [Parameter(Mandatory=$True, HelpMessage='OS Version')]
    [string]$OSVersion,
    [Parameter(Mandatory=$True, ParameterSetName = "CCMCache",HelpMessage='Specify Path to download to')]
    [string]$DownloadPath = "CCMCache",
    [parameter(Mandatory = $false, ParameterSetName = "PreCache", HelpMessage = "Specify a custom path for the PreCache directory, overriding the default CCMCache directory.")]
	[ValidateNotNullOrEmpty()]
	[string]$CustomPath,
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

# Attempt to read TSEnvironment variable MDMUserName
$UserName = $TSEnvironment.Value("MDMUserName")
if (-not ([string]::IsNullOrEmpty($UserName))) {
               
        Log -Message "Successfully read service account user name from TS environment variable 'MDMUserName': $($UserName)" -Type 1 -Component "HPIA" -LogFile $LogFile
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
					# Attempt to read TSEnvironment variable MDMPassword
					$Password = $TSEnvironment.Value("MDMPassword")
					if (-not([string]::IsNullOrEmpty($Password))) {
						Log -Message "Successfully read service account password from TS environment variable 'MDMPassword': ********" -Component "HPIA" -type 3 -LogFile $LogFile
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
$Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList @($UserName, $EncryptedPassword)
       

# Call the AdminService, request Computer Name
# Try / Catch logic borrowed from Invoke-CMApplyDriverPackage.ps1 developed by @NickolajA and @MoDaly_IT
$Filter = "HPIA-$OSversion-HP ProBook 650 G4 8416"
#$Filter = "HPIA-$OSversion-" + (Get-WmiObject -Class:Win32_ComputerSystem).Model + " " + (Get-WmiObject -Class:Win32_BaseBoard).Product


$FilterPackages = "/SMS_Package?`$filter=contains(Name,'$($Filter)')"
$AdminServiceURL = "https://{0}/AdminService/wmi" -f $SiteServer
$AdminServiceUri = $AdminServiceURL + $FilterPackages

try {
        $AdminServiceResponse = Invoke-RestMethod $AdminServiceUri -Method Get -Credential $Credential -ErrorAction Stop  
        $HPIAPackage = $AdminServiceResponse.value  | Select-Object Name,PackageID 
        
        }
catch [System.Security.Authentication.AuthenticationException] {

					
	# Attempt to ignore self-signed certificate binding for AdminService
	# Convert encoded base64 string for ignore self-signed certificate validation functionality
	$CertificationValidationCallbackEncoded = "DQAKACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAdQBzAGkAbgBnACAAUwB5AHMAdABlAG0AOwANAAoAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAB1AHMAaQBuAGcAIABTAHkAcwB0AGUAbQAuAE4AZQB0ADsADQAKACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAdQBzAGkAbgBnACAAUwB5AHMAdABlAG0ALgBOAGUAdAAuAFMAZQBjAHUAcgBpAHQAeQA7AA0ACgAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgAHUAcwBpAG4AZwAgAFMAeQBzAHQAZQBtAC4AUwBlAGMAdQByAGkAdAB5AC4AQwByAHkAcAB0AG8AZwByAGEAcABoAHkALgBYADUAMAA5AEMAZQByAHQAaQBmAGkAYwBhAHQAZQBzADsADQAKACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAcAB1AGIAbABpAGMAIABjAGwAYQBzAHMAIABTAGUAcgB2AGUAcgBDAGUAcgB0AGkAZgBpAGMAYQB0AGUAVgBhAGwAaQBkAGEAdABpAG8AbgBDAGEAbABsAGIAYQBjAGsADQAKACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAewANAAoAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgAHAAdQBiAGwAaQBjACAAcwB0AGEAdABpAGMAIAB2AG8AaQBkACAASQBnAG4AbwByAGUAKAApAA0ACgAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAewANAAoAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAaQBmACgAUwBlAHIAdgBpAGMAZQBQAG8AaQBuAHQATQBhAG4AYQBnAGUAcgAuAFMAZQByAHYAZQByAEMAZQByAHQAaQBmAGkAYwBhAHQAZQBWAGEAbABpAGQAYQB0AGkAbwBuAEMAYQBsAGwAYgBhAGMAawAgAD0APQBuAHUAbABsACkADQAKACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgAHsADQAKACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAUwBlAHIAdgBpAGMAZQBQAG8AaQBuAHQATQBhAG4AYQBnAGUAcgAuAFMAZQByAHYAZQByAEMAZQByAHQAaQBmAGkAYwBhAHQAZQBWAGEAbABpAGQAYQB0AGkAbwBuAEMAYQBsAGwAYgBhAGMAawAgACsAPQAgAA0ACgAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAZABlAGwAZQBnAGEAdABlAA0ACgAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAKAANAAoAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAATwBiAGoAZQBjAHQAIABvAGIAagAsACAADQAKACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgAFgANQAwADkAQwBlAHIAdABpAGYAaQBjAGEAdABlACAAYwBlAHIAdABpAGYAaQBjAGEAdABlACwAIAANAAoAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAWAA1ADAAOQBDAGgAYQBpAG4AIABjAGgAYQBpAG4ALAAgAA0ACgAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIABTAHMAbABQAG8AbABpAGMAeQBFAHIAcgBvAHIAcwAgAGUAcgByAG8AcgBzAA0ACgAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAKQANAAoAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgAHsADQAKACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgAHIAZQB0AHUAcgBuACAAdAByAHUAZQA7AA0ACgAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAfQA7AA0ACgAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAB9AA0ACgAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAfQANAAoAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAAgACAAIAB9AA0ACgAgACAAIAAgACAAIAAgACAA"
	$CertificationValidationCallback = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($CertificationValidationCallbackEncoded))
					
	# Load required type definition to be able to ignore self-signed certificate to circumvent issues with AdminService running with ConfigMgr self-signed certificate binding
	Add-Type -TypeDefinition $CertificationValidationCallback
	[ServerCertificateValidationCallback]::Ignore()
					
	try {
		# Call AdminService endpoint to retrieve package data
		        $Filter = "HPIA-$OSversion-HP ProBook 650 G4 8416"
        #$Filter = "HPIA-$OSversion-" + (Get-WmiObject -Class:Win32_ComputerSystem).Model + " " + (Get-WmiObject -Class:Win32_BaseBoard).Product


        $HPIAPackage = $AdminServiceResponse.value  | Select-Object Name,PackageID 
        
	}
	catch [System.Exception] {
		# Throw terminating error
		$ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
		$PSCmdlet.ThrowTerminatingError($ErrorRecord)
	}
}
catch {
	# Throw terminating error
	$ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
	$PSCmdlet.ThrowTerminatingError($ErrorRecord)
}

# Should have a check to see $HPIAPackage.PackageID contain something.
    
# Setting TS variabels after Admin service has returned correct objects.    
$TSEnvironment.value("OSDDownloadDestinationLocationType") = "$($DownloadPath)"
$TSEnvironment.value("OSDDownloadContinueDownloadOnError") = "1"
$TSEnvironment.value("OSDDownloadDownloadPackages") = "$($HPIAPackage.PackageID)"
$TSEnvironment.value("OSDDownloadDestinationVariable") = "$($Softpaq)"
$ContentPath = $TSEnvironment.Value("softpaq01") 
Log -Message "Setting OSDDownloadDownloadPackages: $($DownloadPath)" -type 1 -LogFile $LogFile
Log -Message "Setting OSDDownloadDownloadPackages: $($HPIAPackage.PackageID)" -type 1 -LogFile $LogFile
Log -Message "Setting OSDDownloadDownloadPackages: $($ContentPath)" -type 1 -LogFile $LogFile
Log -Message "Setting OSDDownloadDownloadPackages: $($HPIAPackage.PackageID)" -type 1 -LogFile $LogFile

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
		log -Message "Failed to download package content with PackageID '$($HPIAPackage.PackageID)'. Return code was: $($ReturnCode)" -Type 3 -Component HPIA -LogFile $LogFile
				
		# Throw terminating error
		$ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
		$PSCmdlet.ThrowTerminatingError($ErrorRecord)
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
        
        Log -Message "nstall Reboot Required — SoftPaq installations are successful, and at least one requires a reboob" -Component "HPIA" -Type 1 -logfile $LogFile

    }
    elseif ($HPIAProcess.ExitCode -eq 256) 
    {
        Log -Message "The analysis returned no recommendation." -Component "HPIA" -Type 2 -logfile $LogFile
        Exit 256
    }
    elseif ($HPIAProcess.ExitCode -eq 4096) 
    {
        Log -Message "This platform is not supported!" -Type 3 -Component "HPIA" -Type 3 -logfile $LogFile
        exit 4096
    }
    elseif ($HPIAProcess.ExitCode -eq 16384) {
        
        Log -Message "No matching configuration found on HP.com" -Type 3 -Component "HPIA" -Type 3 -logfile $LogFile

    }
    Else
    {
        Log -Message "Process exited with code $($Process.ExitCode). Expecting 0." -Component "HPIA" -Log 3
        Exit 
    }
}
catch 
{
    Log -Message "Failed to start the HPImageAssistant.exe: $($_.Exception.Message)" -Component "HPIA" -Log 3
    Exit $($_.Exception.Message)
}

Log -Message "HPIA script is now completed." -Type 3 -Component "HPIA" -Type 3 -logfile $LogFile
