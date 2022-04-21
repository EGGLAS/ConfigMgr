<# Author: Nicklas Eriksson & Daniel GrÃƒÂ¥hns
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
            2.1 - 2022-04-13 - Nicklas Eriksson
                             - Merged ApplyHPIAOnlie.ps1 with ApplyHPIA.ps1 to support both on-prem and access HPIA directly
                              - Added several functions to the script since both part of the script sharing the same code base.
                              - Added check for TS variable 
                                - HPIA_BIOSPassword, leverage HPIA Password for both on-prem and online 
                                - NewComputerModel can be used later in task sequence if you want to get reports if you are insallating a new HP model in your enviroment.
                              - Added paramter Online to support access direct to HPIA.



To-Do:
 - Fallback to latest support OS?
 - Should be able to run script in debug mode.
 - Write back to status message? 
            2.1 - 2022-04-12 - Nicklas Eriksson - If the model does not exists in your enviroment it will set an variable to download drivers online.                                     
 
 How to run the script:
    - ApplyHPIA.ps1 -Siteserver "server.domain.local" 
    - ApplyHPIA.ps1 -Siteserver "server.domain.local" -Online Online -Cleanup
    - ApplyHPIA.ps1 -Siteserver "server.domain.local" -Build "20H2" -Online DoNotFallBackOnline  
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
    [Parameter(Mandatory=$False, HelpMessage='Url to ConfigMgr Adminservice')]
    [string]$SiteServer,
    [parameter(Mandatory=$False, HelpMessage = "Specify the name of BIOS password file.")]
	[string]$BIOSPwd,
    [parameter(Mandatory=$False, HelpMessage = "Specify OS version (Win10|Win11)")]
	[string]$OSVersion,
    [parameter(Mandatory=$False, HelpMessage = "Specify Windows Build (21H2)")]
	[string]$Build,
    [parameter(Mandatory = $false, HelpMessage = "If model does not exist in ConfigMgr, check online or only check online")]
	[ValidateSet("OnlyOnline","FallbackOnline","DoNotFallbackOnline")]
    $Online = "FallbackOnline",
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

function ConnectToAdminservice {
Log -Message "Gathering variabels for adminservice from TS environment variables" -Type 1 -Component "HPIA" -LogFile $LogFile

# Attempt to read TSEnvironment variable AdminserviceUser
$AdminserviceUser = $TSEnvironment.Value("AdminserviceUser")
if (-not ([string]::IsNullOrEmpty($AdminserviceUser))) {
               
        Log -Message " - Successfully read service account user name from TS environment variable 'Adminserviceuser': ********" -Type 1 -Component "HPIA" -LogFile $LogFile
    }
else {
        Log -Message " - Required service account user name could not be determined from TS environment variable 'Adminserviceuser'" -type 3 -Component "HPIA" -LogFile $LogFile
        $Errorcode = "Required service account user name could not be determined from TS environment variable"
        (new-object -ComObject Microsoft.SMS.TsProgressUI).CloseProgressDialog() ; (new-object -ComObject wscript.shell).Popup("$($Errorcode) ",0,'Warning',0x0 + 0x30) ; Exit 0
    }

# Validate correct value have been either set as a TS environment variable or passed as parameter input for service account password used to authenticate against the AdminService

# Attempt to read TSEnvironment variable AdminservicePassword
$Password = $TSEnvironment.Value("AdminservicePassword")
if (-not([string]::IsNullOrEmpty($Password))) 
{
	Log -Message " - Successfully read service account password from TS environment variable 'AdminservicePassword': ********" -Component "HPIA" -type 1 -LogFile $LogFile
}
else
{
	Log -message " - Required service account password could not be determined from TS environment variable" -Component "HPIA" -type 3 -LogFile $LogFile
    $Errorcode = "Required service account password could not be determined from TS environment variable"
    (New-Object -ComObject Microsoft.SMS.TsProgressUI).CloseProgressDialog() ; (new-object -ComObject wscript.shell).Popup("$($Errorcode) ",0,'Warning',0x0 + 0x30) ; Exit 0

}

# Construct PSCredential object for authentication
$EncryptedPassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
$Global:Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList @($AdminserviceUser, $EncryptedPassword)

}

function CheckOS {
Log -Message "Process to determine what OS installed" -Component "HPIA" -type 1 -LogFile $LogFile

    # Variables for ConfigMgr Adminservice
if ([string]::IsNullOrEmpty($OSVersion))
{
    Log -Message " - OSVersion is not specified, getting OSVersion from WMI" -Component "HPIA" -type 1 -LogFile $LogFile
    $WindowsOSCaption = (Get-CimInstance win32_OperatingSystem).Caption
    Log -Message " - Current OS Caption: $WindowsOSCaption" -Component "HPIA" -type 1 -LogFile $LogFile
    
    if ($WindowsOSCaption -like "Microsoft Windows 11*")
    {
        Log -Message " - Setting OSMajorVersion to Win11" -Component "HPIA" -type 1 -LogFile $
        $OSMajorVersion = "Win11"

    }
    elseif ($WindowsOSCaption -like "Microsoft Windows 10*")
    {
        Log -Message " - Setting OSMajorVersion to Win10" -Component "HPIA" -type 1 -LogFile $LogFile
        $Global:OSMajorVersion = "Win10"
    }
}
else
{
    Log -Message " - OSVersion was specified, setting OSMajorVersion to $OSVersion" -Component "HPIA" -type 1 -LogFile $LogFile
    $Global:OSMajorVersion = $OSVersion
}

if ([string]::IsNullOrEmpty($Build))
{
    $Global:WindowsBuild = Get-ItemPropertyValue "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name DisplayVersion
    Log -Message " - OSBuild was not specified, getting OSBuild from registry: $($Global:WindowsBuild)" -Component "HPIA" -type 1 -LogFile $LogFile

}
else
{
    $Global:WindowsBuild = $Build
    Log -Message " - OSBuild was specified: $($Global:WindowsBuild)" -Component "HPIA" -type 1 -LogFile $LogFile

}
}

function WriteComputerInfo {
    $Global:Baseboard = (Get-CimInstance -ClassName win32_baseboard).Product
    $Global:Computersystem = (Get-CimInstance -ClassName win32_computersystem).Model
    log -Message "Gathering information from the computer:" -Type 1 -Component HPIA -LogFile $LogFile				        
    log -Message " - Computermodel: $($Computersystem)" -Type 1 -Component HPIA -LogFile $LogFile				        
    log -Message " - Baseboard: $($Baseboard)" -Type 1 -Component HPIA -LogFile $LogFile
    
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

function CustomTSVariable {
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
}

Function StartHPIA {
try
    { 

        # Start HPIA Update process 
        Log -Message "Starting HPIA installation." -type 1 -Component "HPIA" -LogFile $LogFile
        Log -Message " - Arguments: $Argument" -type 1 -Component "HPIA" -LogFile $LogFile

        $HPIAProcess = Start-Process -Wait -FilePath "HPImageAssistant.exe" -WorkingDirectory "$SoftpaqDownloadFolder" -ArgumentList "$Argument" -PassThru
        $Handle = $HPIAProcess.Handle # Cache Info $HPIAProcess.Handle
        $HPIAProcess.WaitForExit();
        $HPIAProcess.ExitCode


        If ($HPIAProcess.ExitCode -eq 0)
        {
            
            Log -Message "Installation is completed" -Component "HPIA" -Type 1 -logfile $LogFile
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
            Exit 16384
        }
        elseif ($HPIAProcess.ExitCode -eq 4097) {
            Log -Message " - HPIA installation failed" -Type 3 -Component "HPIA" -logfile $LogFile
            Log -Message " - The parameters are invalid, check $HPIALogFile for more information." -Type 3 -Component "HPIA" -logfile $LogFile
            $Errorcode = "The parameters are invalid, check $LogFile or $HPIALogFile might contain more information."
            #(new-object -ComObject Microsoft.SMS.TsProgressUI).CloseProgressDialog() ; (new-object -ComObject wscript.shell).Popup("$($Errorcode) ",0,'Warning',0x0 + 0x30) ; Exit 0
            Exit 4097

        }
        elseif ($HPIAProcess.ExitCode -eq 8199) {
            Log -Message " - The SoftPaq download failed, check $HPIALogFile more information." -Type 2 -Component "HPIA" -logfile $LogFile
            Log -Message " - Ignoring this error message, HPIA installation was done succesfully" -Type 2 -Component "HPIA" -logfile $LogFile
            Log -Message "Process exited with code $($HPIAProcess.ExitCode). This is the same as Exit code 0 ." -type 1 -Component "HPIA" -LogFile $LogFile
            Log -Message "Installation is completed" -Component "HPIA" -Type 1 -logfile $LogFile
            
        }
        Else
        {
            Log -Message "Process exited with code $($HPIAProcess.ExitCode). Expecting 0." -type 1 -Component "HPIA" -LogFile $LogFile
            $Errorcode = "Process exited with code $($HPIAProcess.ExitCode) . Expecting 0." 
        }

        if ($ExtraFilesCheck)
        {
            Log -Message "Checking if there are any extra SP files to install" -Type 1 -Component "HPIA" -LogFile $LogFile
            $ExtraSPFilesPath = Join-Path $SoftpaqDownloadFolder "ExtraSPFiles"
            if (Test-Path $ExtraSPFilesPath)
            {
                $ExtraSPFiles = Get-ChildItem $ExtraSPFilesPath | Where-Object {$_.Name -like "sp*.exe"}
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
            $ExtraINFFilesPath = Join-Path $SoftpaqDownloadFolder "ExtraINFFiles"
            if (Test-Path $ExtraINFFilesPath)
            {
                $ExtraINFFiles = Get-ChildItem $ExtraINFFilesPath -Recurse | Where-Object {$_.Name -like "*.inf"}
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
    
# Construct TSEnvironment object
try {
    $TSEnvironment = New-Object -ComObject Microsoft.SMS.TSEnvironment -ErrorAction Stop
}
catch [System.Exception] {
    Write-Warning -Message "Unable to construct Microsoft.SMS.TSEnvironment object" ; exit 3
}

# Set script settings.
$Scriptversion = "2.1"
$LogFile = $TSEnvironment.Value("_SMSTSLogPath") + "\ApplyHPIA.log" # ApplyHPIA log location 
$Softpaq = "SOFTPAQ"
$HPIALogFile = $TSEnvironment.Value("_SMSTSLogPath") + "\HPIAInstall" # Log location for HPIA install.

Log -Message "HPIA is about to start..." -type 1 -Component "HPIA" -LogFile $LogFile
Log -Message " - Loading script with version: $Scriptversion" -type 1 -Component "HPIA" -LogFile $LogFile
Log -Message " - PS variable 'Online' was set to : $Online" -type 1 -Component "HPIA" -LogFile $LogFile


if ($Online -eq "FallbackOnline" -or "DoNotFallbackOnline")
{
    Log -Message "Script was set to check if package exists in ConfigMgr" -type 1 -Component "HPIA" -LogFile $LogFile
    
    # Call function ConnectToAdminService
    ConnectToAdminservice

    CheckOS
    WriteComputerInfo
    
    # adminservice uses theese variables to download package
    $Filter = "HPIA-$OSMajorVersion-$WindowsBuild-" + "$Computersystem" + " " + "$Baseboard"
    $FilterPackages = "/SMS_Package?`$filter=contains(Name,'$($Filter)')"
    $AdminServiceURL = "https://{0}/AdminService/wmi" -f $SiteServer
    $AdminServiceUri = $AdminServiceURL + $FilterPackages
    log -Message "Using this filter to attempt to get the correct driver package from adminservice: $($Filter)" -Type 1 -Component HPIA -LogFile $LogFile				        

    try {
            log -Message " - Accessing adminservice with the following URL: $($AdminServiceUri)" -Type 1 -Component HPIA -LogFile $LogFile				        
            $AdminServiceResponse = Invoke-RestMethod $AdminServiceUri -Method Get -Credential $Credential -ErrorAction Stop

            $CheckifAdminServiceResponseIsNull =  $AdminServiceResponse.value | Select-Object Name
            
            if (-not [string]::IsNullOrEmpty($CheckifAdminServiceResponseIsNull)) 
            {
                
                log -Message " - Grabbing propertys Name and PackageID from the driverpackage" -Type 1 -Component HPIA -LogFile $LogFile				  
                $HPIAPackage = $AdminServiceResponse.value  | Select-Object Name,PackageID 
                log -Message "  - Name: $($HPIAPackage.Name)" -Type 1 -Component HPIA -LogFile $LogFile				
                log -Message "  - PackageID: $($HPIAPackage.PackageID)" -Type 1 -Component HPIA -LogFile $LogFile
                log -Message "Found the correct driver package from adminservice:" -Type 1 -Component HPIA -LogFile $LogFile				
            }
            else 
            {
                log -Message " - Did not find any matching model package in ConfigMgr for $filter" -Type 1 -Component HPIA -LogFile $LogFile				  
            }			
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
                log -Message " - Accessing adminservice with following URL: $($AdminServiceUri)" -Type 1 -Component HPIA -LogFile $LogFile				
                $AdminServiceResponse = Invoke-RestMethod $AdminServiceUri -Method Get -Credential $Credential -ErrorAction 
                
            $CheckifAdminServiceResponseIsNull =  $AdminServiceResponse.value | Select-Object Name
               
                if (-not [string]::IsNullOrEmpty($CheckifAdminServiceResponseIsNull)) 
                {
                    
                    log -Message " - Grabbing propertys Name and PackageID from the driverpackage" -Type 1 -Component HPIA -LogFile $LogFile				  
                    $HPIAPackage = $AdminServiceResponse.value  | Select-Object Name,PackageID 
                    log -Message "  - Name: $($HPIAPackage.Name)" -Type 1 -Component HPIA -LogFile $LogFile				
                    log -Message "  - PackageID: $($HPIAPackage.PackageID)" -Type 1 -Component HPIA -LogFile $LogFile
                    log -Message "Found the correct driver package from adminservice:" -Type 1 -Component HPIA -LogFile $LogFile				
                }
                else 
                {
                    log -Message " - Did not find any matching model package in ConfigMgr for $filter" -Type 1 -Component HPIA -LogFile $LogFile				  
                }
	        }
	    catch [System.Exception] {
		        log -Message "Someting went wrong.." -Type 3 -Component Error -LogFile $LogFile
                Log -Message " - Error code: $($_.Exception.Message)" -Type 3 -Component "Error" -LogFile $LogFile
				
                $Errorcode = "Failed to retrive driver package from ConfigMgr Adminservice for $($Filter), please check logfile $LogFile for more information."
        
                if (-not $Online -eq "FallbackOnline") {

                    (new-object -ComObject Microsoft.SMS.TsProgressUI).CloseProgressDialog() ; (new-object -ComObject wscript.shell).Popup("$($Errorcode) ",0,'Warning',0x0 + 0x30) ; Exit 0
                    Throw
                }
                else 
                {
                    log -Message " - Failed to retrive driver package from ConfigMgr Adminservice for $($Filter)." -Type 1 -Component HPIA -LogFile $LogFile				
                    log -Message " - Since parameter Online was set to $($Online), checking Online" -Type 1 -Component HPIA -LogFile $LogFile				

                }
	        }
        }
    catch {
	        # Throw error code
		    Log -Message "Someting went wrong.." -Type 3 -Component Error -LogFile $LogFile
            Log -Message " - Error code: $($_.Exception.Message)" -Type 3 -Component "Error" -LogFile $LogFile
            $Errorcode = "Failed to retrive driver package from ConfigMgr Adminservice for $($Filter), please check logfile $LogFile for more information."
            
            if (-not $Online -eq "FallbackOnline") {

                (new-object -ComObject Microsoft.SMS.TsProgressUI).CloseProgressDialog() ; (new-object -ComObject wscript.shell).Popup("$($Errorcode) ",0,'Warning',0x0 + 0x30) ; Exit 0
                Throw
            }
            else 
            {
                Log -Message " - Failed to retrive driver package from ConfigMgr Adminservice for $($Filter)." -Type 2 -Component HPIA -LogFile $LogFile				
                Log -Message " - Since parameter Online was set to $($Online), contiune to the online section..." -Type 1 -Component HPIA -LogFile $LogFile				

            }
        }


    if (-not [string]::IsNullOrEmpty($HPIAPackage.Name))
    {
    # Setting TS variabels after Admin service has returned correct objects.
    log -message "Setting TS variables for package content download process" -Type 1 -Component HPIA -LogFile $LogFile
    
    $TSEnvironment.value("OSDDownloadDestinationLocationType") = "$($DownloadPath)"
    $TSEnvironment.value("OSDDownloadContinueDownloadOnError") = "1"
    $TSEnvironment.value("OSDDownloadDownloadPackages") = "$($HPIAPackage.PackageID)"
    $TSEnvironment.value("OSDDownloadDestinationVariable") = "$($Softpaq)"

    Log -Message " - Setting OSDDownloadDownloadPackages: $($DownloadPath)" -type 1 -LogFile $LogFile -Component HPIA
    Log -Message " - Setting OSDDownloadContinueDownloadOnError: 1" -type 1 -LogFile $LogFile -Component HPIA
    Log -Message " - Setting OSDDownloadDownloadPackages: $($HPIAPackage.PackageID)" -type 1 -LogFile $LogFile -Component HPIA
    Log -Message " - Setting OSDDownloadDestinationVariable: $($Softpaq)" -type 1 -LogFile $LogFile -Component HPIA

    CustomTSVariable

    # Download Drivers with OSDDownloadContent
    log -message "Starting package content download process, this might take some time" -Type 1 -Component HPIA -LogFile $LogFile
    $ReturnCode = Invoke-Executable -FilePath (Join-Path -Path $env:windir -ChildPath "CCM\OSDDownloadContent.exe")

    # Match on return code
	if ($ReturnCode -eq 0) {
		log -message "Successfully downloaded package content with PackageID: $($HPIAPackage.PackageID)" -Type 1 -Component HPIA -LogFile $LogFile
        write-host "Successfully downloaded package content with PackageID: $($HPIAPackage.PackageID)" -ForegroundColor green
	}
	else {
            # Throw error code
		    Log -Message "Someting went wrong.." -Type 3 -Component Error -LogFile $LogFile
            Log -Message " - Error code: $($_.Exception.Message)" -Type 3 -Component "Error" -LogFile $LogFile
            $Errorcode = "Failed to retrive driver package from ConfigMgr Adminservice for $($Filter), please check logfile $LogFile for more information."
            
            if (-not $Online -eq "FallbackOnline") {

                (new-object -ComObject Microsoft.SMS.TsProgressUI).CloseProgressDialog() ; (new-object -ComObject wscript.shell).Popup("$($Errorcode) ",0,'Warning',0x0 + 0x30) ; Exit 0
                Exit 1
            }
            else 
            {
                log -Message "Failed to retrive driver package from ConfigMgr Adminservice for $($Filter)." -Type 2 -Component HPIA -LogFile $LogFile				
                log -Message "- Since parameter Online was set to $($Online), the script will move on to the online section..." -Type 2 -Component HPIA -LogFile $LogFile				
               
            }
				
	}
    
        # Set Softpaq to Softpaq01 to get an working directory. 
        $SoftpaqDownloadFolder = $TSEnvironment.Value("softpaq01") 
        Log -Message " - Setting TS variable Softpaq01: $($SoftpaqDownloadFolder)" -type 1 -LogFile $LogFile -Component HPIA
        
        log -Message "Starting to reset the task sequence variable that were used to download drivers" -Type 1 -Component HPIA -LogFile $LogFile
        $TSEnvironment.Value("OSDDownloadDownloadPackages") = [System.String]::Empty	
        $TSEnvironment.Value("OSDDownloadDestinationLocationType") = [System.String]::Empty
        $TSEnvironment.Value("OSDDownloadDestinationVariable") = [System.String]::Empty
        $TSEnvironment.Value("OSDDownloadDestinationPath") = [System.String]::Empty
        
        log -Message " - Setting task sequence variable OSDDownloadDownloadPackages to a blank value" -Type 1 -Component HPIA -LogFile $LogFile
        log -Message " - Setting task sequence variable OSDDownloadDestinationLocationType to a blank value" -Type 1 -Component HPIA -LogFile $LogFile
        log -Message " - Setting task sequence variable OSDDownloadDestinationVariable to a blank value" -Type 1 -Component HPIA -LogFile $LogFile
        log -message " - Setting task sequence variable OSDDownloadDestinationPath to a blank value" -Type 1 -Component HPIA -LogFile $LogFile

        if (-not $PreCache) {
        # Check for BIOS File.
            if (-not [string]::IsNullOrEmpty($BIOSPwd)) 
            {
                 Log -Message "Check if BIOS file exists." -type 1 -Component "HPIA" -LogFile $LogFile  
                 $BIOSPwd = Get-childitem -Path $SoftpaqDownloadFolder -Filter "*.bin"
                 $Argument = "/Operation:Analyze /Action:install /Selection:All /OfflineMode:Repository /noninteractive /Debug /SoftpaqDownloadFolder:$SoftpaqDownloadFolder /ReportFolder:$($HPIALogFile) /BIOSPwdFile:$($BIOSPwd)"              
                 Log -Message "BIOS file found, will start HPIA with following install arguments: $($Argument)." -type 1 -Component "HPIA" -LogFile $LogFile  
               
            }
            elseif (-not [string]::IsNullOrEmpty($TSEnvironment.Value("HPIA_BIOSPassword")))
            {
                # Get BIOS variable
                $BIOSPassword = $TSEnvironment.Value("HPIA_BIOSPassword")
                if (-not([string]::IsNullOrEmpty($BIOSPassword))) 
                {
                    Log -Message "Attempting to read BIOS password from TS environment variable 'HPIA_BIOSPassword'" -Type 1 -Component "HPIA" -LogFile $LogFile
                    Log -Message " - Successfully read BIOS password from TS environment variable 'HPIA_BIOSPassword': ********" -Type 1 -Component "HPIA" -LogFile $LogFile
                    [System.Environment]::SetEnvironmentVariable('biospass',"$BIOSPassword") #Set BIOS Password as environment variable, will be cleared on last line in script.
                    #$Argument = "/Operation:Analyze /Action:install /Selection:All /OfflineMode:Repository /noninteractive /Debug /SoftpaqDownloadFolder:$($SoftpaqDownloadFolder) /ReportFolder:$($HPIALogFile) /BIOSPwdEnv:biospass"
                    $Argument = "/Action:install /Selection:All /OfflineMode:Repository /noninteractive /Debug /SoftpaqDownloadFolder:$($SoftpaqDownloadFolder) /ReportFolder:$($HPIALogFile) /BIOSPwdEnv:biospass"
                    Log -Message "BIOS enviroment variable found, will start HPIA with following install arguments: $($Argument)." -type 1 -Component "HPIA" -LogFile $LogFile                 

                }
            }
            else 
            {
                 $Argument = "/Operation:Analyze /Action:install /Selection:All /OfflineMode:Repository /noninteractive /Debug /SoftpaqDownloadFolder:$SoftpaqDownloadFolder /ReportFolder:$($HPIALogFile)" 
                 Log -Message "BIOSPassword file or enviroment variable could not be found, will start HPIA with following install arguments: $($Argument)." -type 1 -Component "HPIA" -LogFile $LogFile  
 
            }
             Set-Location -Path $SoftpaqDownloadFolder
             StartHPIA
            
            # Clear BIOSPassword
            $TSEnvironment.Value("OSDDownloadDestinationPath") = [System.String]::Empty
            [System.Environment]::SetEnvironmentVariable('biospass','Secret')
            Log -Message "Successfully cleared BIOSPassword enviroment variable" -type 1 -Component "HPIA" -LogFile $LogFile  


     }
        else {
            Log -Message "Script is running as Precache, skipping to install HPIA." -Type 2 -Component "HPIA" -logfile $LogFile   
        }
    
}
    else 
    {
        
        if (-not $Online -eq "FallbackOnline") {
            log -Message "Someting went wrong.." -Type 3 -Component Error -LogFile $LogFile
            Log -Message " - Error code: $($_.Exception.Message)" -Type 3 -Component "Error" -LogFile $LogFile
            log -Message " - Failed to retrive driver package from ConfigMgr Adminservice for $($Filter)." -Type 1 -Component HPIA -LogFile $LogFile				
		
            $Errorcode = "Failed to retrive driver package from ConfigMgr Adminservice for $($Filter), please check logfile $LogFile for more information."

            (new-object -ComObject Microsoft.SMS.TsProgressUI).CloseProgressDialog() ; (new-object -ComObject wscript.shell).Popup("$($Errorcode) ",0,'Warning',0x0 + 0x30) ; Exit 0
            Throw
        }
        else 
        {
            log -Message "Failed to retrive driver package from ConfigMgr Adminservice for $($Filter)." -Type 1 -Component HPIA -LogFile $LogFile				
            log -Message " - Since parameter Online was set to $($Online), falling back to online mode" -Type 1 -Component HPIA -LogFile $LogFile				
            $FallbackOnline = "NewModel"
            log -Message " - Updating variable 'FallbackOnline' to: NewModel" -Type 1 -Component HPIA -LogFile $LogFile				

        }       
    }
}

if (($Online -eq "Online") -or ($FallbackOnline -eq "NewModel")) {
    
    Log -Message "Script is running as '$Online'" -Type 1 -Component "HPIA" -logfile $LogFile 
    
    $HPIAPath = "C:\HPIA"
    Log -Message "Setting PS variable 'HPIAPath' to: $HPIAPath" -Type 1 -Component "HPIA" -logfile $LogFile 


    CheckOS
    WriteComputerInfo
    
    if ($Online -eq "FallbackOnline")
    {
        Log -Message "New computermodel found updating TS variable 'NewComputerModel' with the following value: $NewComputerModel" -Type 1 -Component "HPIA" -logfile $LogFile
         
        $NewComputerModel = $Baseboard + "," + $ComputerSystem + "," + "$WindowsBuild" + "," + "$OSMajorVersion"
        $TSEnvironment.value("OSDDownloadDownloadPackages") = "$($NewComputerModel)"

        Log -Message " - Done with updating TS variable 'NewComputerModel'" -Type 1 -Component "HPIA" -logfile $LogFile 

    }

    #Setup LOCALAPPDATA Variable
    [System.Environment]::SetEnvironmentVariable('LOCALAPPDATA',"$env:SystemDrive\Windows\system32\config\systemprofile\AppData\Local")

    $WorkingDir = $env:TEMP
    
    #PowerShellGet from PSGallery URL
    # Kommentar gå genom detta med Daniel, hur blir det vid nya versioenr?
    if (!(Get-Module -Name PowerShellGet)){
        $PowerShellGetURL = "https://psg-prod-eastus.azureedge.net/packages/powershellget.2.2.5.nupkg"
        Log -Message "Downloading module PowerShellGet" -Type 1 -Component "HPIA" -LogFile $LogFile
        Invoke-WebRequest -UseBasicParsing -Uri $PowerShellGetURL -OutFile "$WorkingDir\powershellget.2.2.5.zip"
        $Null = New-Item -Path "$WorkingDir\2.2.5" -ItemType Directory -Force
        Expand-Archive -Path "$WorkingDir\powershellget.2.2.5.zip" -DestinationPath "$WorkingDir\2.2.5"
        $Null = New-Item -Path "$env:ProgramFiles\WindowsPowerShell\Modules\PowerShellGet" -ItemType Directory -ErrorAction SilentlyContinue
        Log -Message " - Moving module PowershellGet to $($env:ProgramFiles)\WindowsPowerShell\Modules\PowerShellGet\2.2.5" -Type 1 -Component "HPIA" -LogFile $LogFile
        Move-Item -Path "$WorkingDir\2.2.5" -Destination "$env:ProgramFiles\WindowsPowerShell\Modules\PowerShellGet\2.2.5"
    }

    #PackageManagement from PSGallery URL 
    # Kommentar gå genom detta med Daniel, hur blir det vid nya versioenr?
    if (!(Get-Module -Name PackageManagement)){
        $PackageManagementURL = "https://psg-prod-eastus.azureedge.net/packages/packagemanagement.1.4.7.nupkg"
        Invoke-WebRequest -UseBasicParsing -Uri $PackageManagementURL -OutFile "$WorkingDir\packagemanagement.1.4.7.zip"
        $Null = New-Item -Path "$WorkingDir\1.4.7" -ItemType Directory -Force
        Expand-Archive -Path "$WorkingDir\packagemanagement.1.4.7.zip" -DestinationPath "$WorkingDir\1.4.7"
        $Null = New-Item -Path "$env:ProgramFiles\WindowsPowerShell\Modules\PackageManagement" -ItemType Directory -ErrorAction SilentlyContinue
        Log -Message " - Moving module PackageManagement to $($env:ProgramFiles)\WindowsPowerShell\Modules\PackageManagement\1.4.7" -Type 1 -Component "HPIA" -LogFile $LogFile
        Move-Item -Path "$WorkingDir\1.4.7" -Destination "$env:ProgramFiles\WindowsPowerShell\Modules\PackageManagement\1.4.7"
        }
    
    #Import PowerShellGet
    Import-Module PowerShellGet
    
    #Install Module HPCMSL from PSGallery
    $ModuleName = "HPCMSL"
    Log -Message "Installing module $ModuleName" -Type 1 -Component "HPIA" -LogFile $LogFile

    Install-Module -Name $ModuleName -Force -AcceptLicense -SkipPublisherCheck
    Log -Message " - Starting to import module" -Type 1 -Component "HPIA" -LogFile $LogFile
    Import-Module -Name $ModuleName -Force
    Log -Message " - Successfully installed and impoorted module $ModuleName" -Type 1 -Component "HPIA" -LogFile $LogFile


    Log -Message "Creating HPIA Folder: $HPIAPath" -type 1 -Component "HPIA" -LogFile $LogFile
    New-Item -ItemType Directory -Path $HPIAPath -ErrorAction Silentlycontinue
    Log -Message " - Successfully created folder: $HPIAPath" -type 1 -Component "HPIA" -LogFile $LogFile

    Log -Message "----- Starting Remediation for Module $ModuleName -----" -Type 2 -LogFile $LogFile
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 # Force Powershell to use TLS1.2
    Log -Message " - Forcing Powershell to use TLS1.2" -Type 2 -LogFile $LogFile
    Write-Output " - Forcing Powershell to use TLS1.2 $RequiredVersion"
    [version]$RequiredVersion = (Find-Module -Name $ModuleName).Version
    $status = $null
    $Status = Get-InstalledModule -Name $ModuleName -ErrorAction SilentlyContinue
    if ($Status.Version -lt $RequiredVersion)
    {
    if ($Status){Uninstall-Module $ModuleName -AllVersions -Force}
    Write-Output "Installing $ModuleName to Latest Version $RequiredVersion"
    Log -Message " - Installing $ModuleName to Latest Version $RequiredVersion" -Type 1 -LogFile $LogFile
    Install-Module -Name $ModuleName -Force -AllowClobber -AcceptLicense -Scope AllUsers
    
    #Confirm
    $InstalledVersion = [Version](Get-InstalledModule -Name $ModuleName -ErrorAction SilentlyContinue).Version
    if (!($InstalledVersion)){$InstalledVersion = '1.0.0.1'}
        if ($InstalledVersion -ne $RequiredVersion)
        {
            Write-Output "Failed to Upgrade Module $ModuleName to $RequiredVersion"
            Write-Output "Currently on Version $InstalledVersion"
            Log -Message "Failed to Upgrade Module $ModuleName to $RequiredVersion" -Type 3 -LogFile $LogFile
            Log -Message "Currently on Version $InstalledVersion" -Type 3 -LogFile $LogFile
        }
    elseif ($InstalledVersion -ne $RequiredVersion)
        {
            Write-Output "Successfully Upgraded Module $ModuleName to $RequiredVersion"
            Log -Message "Successfully Upgraded Module $ModuleName to $RequiredVersion" -Type 1 -LogFile $LogFile
        }
    }
    else
    {
        Write-Output "$ModuleName already Installed with $($Status.Version)"
        Log -Message " - $ModuleName already Installed with $($Status.Version)" -Type 1 -LogFile $LogFile
    }

    Set-Location -Path $HPIAPath
    Log -Message "Starting to install HPIA" -Type 1 -LogFile $LogFile

    try
    {
        Install-HPImageAssistant -Extract -DestinationPath $HPIAPath -ErrorAction stop

    }
    catch 
    {
        Log -Message "Someting went wrong.." -Type 3 -Component Error -LogFile $LogFile
        Log -Message " - Error code: $($_.Exception.Message)" -Type 3 -Component "Error" -LogFile $LogFile

    }
    
    if (Test-Path "$HPIAPath\HPImageAssistant.exe")
    {
        Write-Output "HPIA Downloaded and installed"
        Log -Message " - HPIA Downloaded and installed" -Type 1 -LogFile $LogFile
    }
    else
    {
        Write-Output "HPIA install Failed"
        Log -Message " - HPIA install Failed" -Type 1 -LogFile $LogFile
        Exit 404
    }

        if (Test-Path "$HPIAPath\Repository")
        {
            Log -Message " - Repository for HPIA exists, no need to create folder structure" -type 1 -LogFile $LogFile -Component HPIA

            Set-Location -Path "$HPIAPath\Repository"
            Log -Message " - Starting Initialize-Repository" -Type 1 -LogFile $LogFile
            Initialize-Repository
        }
        else
        {
            Log -Message " - Repository for HPIA did not exists, creating folder" -type 1 -LogFile $LogFile -Component HPIA
            New-Item -ItemType Directory -Path "$HPIAPath\Repository" -ErrorAction Stop
            Set-Location -Path "$HPIAPath\Repository"
            Initialize-Repository
        }
        
    Add-RepositoryFilter -platform $Baseboard -os "$OSMajorVersion"-osver $WindowsBuild -category dock
    Log -Message " - Applying repository filter to $Computersystem repository to download: Dock" -type 1 -LogFile $LogFile -Component HPIA
    
    Add-RepositoryFilter -platform $Baseboard -os "$OSMajorVersion"-osver $WindowsBuild -category driver
    Log -Message " - Applying repository filter to $Computersystem repository to download: Driver" -type 1 -LogFile $LogFile -Component HPIA
    
    Add-RepositoryFilter -platform $Baseboard -os "$OSMajorVersion"-osver $WindowsBuild -category firmware
    Log -Message " - Applying repository filter to $Computersystem repository to download: Firmware" -type 1 -LogFile $LogFile -Component HPIA
    
    Add-RepositoryFilter -platform $Baseboard -os "$OSMajorVersion"-osver $WindowsBuild -category bios
    Log -Message " - Applying repository filter to $Computersystem repository to download: BIOS" -type 1 -LogFile $LogFile -Component HPIA

    Log -Message " - Invoking repository sync with the following filter (might take some time):" -type 1 -LogFile $LogFile -Component HPIA
    Log -Message "   - Computersystem: $Computersystem" -Type 1 -LogFile $LogFile -Component HPIA
    Log -Message "   - Baseboard: $Baseboard" -Type 1 -LogFile $LogFile -Component HPIA
    Log -Message "   - OSMajorversion: $OSMajorVersion" -Type 1 -LogFile $LogFile -Component HPIA
    Log -Message "   - WindowsBuild: $WindowsBuild" -Type 1 -LogFile $LogFile -Component HPIA

    Write-Output "Invoking repository sync for $Computersystem $Baseboard. OS: "$OSMajorVersion", $WindowsBuild (might take some time)"
    try
    {
        Log -Message " - Starting Repository sync" -LogFile $LogFile -Type 1 -Component HPIA
        Set-RepositoryConfiguration -Setting OfflineCacheMode -CacheValue Enable
        Start-Sleep -s 15
        Invoke-RepositorySync -Quiet

        Log -Message " - Repository sync is successful" -Type 1 -LogFile $LogFile -Component HPIA
        Write-Output "Repository sync is successful"
    }
    catch
    {
        Log -Message " - Repository sync  NOT successful" -LogFile $LogFile -Component HPIA -Type 3
        Write-Output "Repository sync NOT successful"
        Log -Message " - Error code: $($_.Exception.Message)" -Type 3 -Component "Error" -LogFile $LogFile
        Exit 1 # La till Exit code här behövs det?!

    }
    Start-Sleep -s 15

    If($LTSC){
        Log -Message "Script set to run as LTSC, must rename cab file" -LogFile $LogFile -Component HPIA -Type 2
        $CabName = (Get-ItemProperty $HPIAPath\Repository\.repository\cache\*.cab).name
        $CabNewName = ((Get-ItemProperty $HPIAPath\Repository\.repository\cache\*.cab).name).Replace(".cab", ".e.cab")
        Rename-Item -path "$HPIAPath\Repository\.repository\cache\$CabName" -newname $CabNewName
        Log -Message " - Rename $CabName to $CabNewName" -LogFile $LogFile -Component HPIA -Type 2
        Log -Message "LTSC section is now done" -LogFile $LogFile -Component HPIA -Type 2


    }
    Set-Location "$HPIAPath\"
    
    if (-not $PreCache)
    {
      $SoftpaqDownloadFolder = $HPIAPath  
        Log -Message "Attempting to read BIOS password from TS environment variable 'HPIA_BIOSPassword'" -Type 1 -Component "HPIA" -LogFile $LogFile
        # Get BIOS variable
        $BIOSPassword = $TSEnvironment.Value("HPIA_BIOSPassword")
        if (-not([string]::IsNullOrEmpty($BIOSPassword))) 
        {
            Log -Message " - Successfully read BIOS password from TS environment variable 'HPIA_BIOSPassword': ********" -Type 1 -Component "HPIA" -LogFile $LogFile

            # Clear task sequence variable for HP Password.
            $TSEnvironment.Value("HPIA_BIOSPassword") = [System.String]::Empty
            [System.Environment]::SetEnvironmentVariable('biospass',"$BIOSPassword") #Set BIOS Password as environment variable, will be cleared on last line in script.
            Log -Message " - Setting task sequence variable 'HPIA_BIOSPassword' to a blank value" -Type 1 -Component "HPIA" -logfile $LogFile
            $Argument = "/Operation:Analyze /Action:install /Selection:All /OfflineMode:Repository /noninteractive /Debug /SoftpaqDownloadFolder:$($SoftpaqDownloadFolder) /ReportFolder:$($HPIALogFile) /BIOSPwdEnv:biospass"
            Log -Message "BIOSPassword enviroment found, will start HPIA with following install arguments: $($Argument)." -type 1 -Component "HPIA" -LogFile $LogFile  

        }
        Else
        {
            $Argument = "/Operation:Analyze /Action:install /Selection:All /OfflineMode:Repository /noninteractive /Debug /SoftpaqDownloadFolder:$($SoftpaqDownloadFolder) /ReportFolder:$($HPIALogFile)" 
            Log -Message "BIOSPassword enviroment variable could not be found, will start HPIA with following install arguments: $($Argument)." -type 1 -Component "HPIA" -LogFile $LogFile  

        }


        StartHPIA

    }
    else {
            Log -Message "Script is running as Precache, skipping to install HPIA." -Type 2 -Component "HPIA" -logfile $LogFile   
        }
        
    [System.Environment]::SetEnvironmentVariable('biospass','Secret')
    Log -Message "Successfully cleared BIOSPassword enviroment variable" -type 1 -Component "HPIA" -LogFile $LogFile  
}

Log -Message "HPIA process is now complete" -Component "HPIA" -Type 1 -logfile $LogFile
Log -Message "---------------------------------------------------------------------------------------------------------------------------------------------------" -type 1 -Component "HPIA" -LogFile $LogFile
