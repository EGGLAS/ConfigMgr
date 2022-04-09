<# Author: Daniel Gråhns
 Date: 2022-04-01
Script for Task Sequence after ConfigMgr client installed to download all softpaqs for HP model and install during OSD
	1 Install Modules
	2 Download all Softpaqs from Internet for HP model running OSD and create repository
	3 Install all Drivers, Firmware, BIOS and Dock during OSD from local repository

 Version: 0.9
 Changelog:  0.9 - 2022-04-01 - Daniel Gråhns - Script Created
             1.0 - 2022-04-04 - Nicklas Eriksson - THIS VERSION IS STILL IN BETA!
                                - Added OSVersion, OSBuild and LTSC as parameters.
                                - Changed BIOS to handle trough task sequences variable.

How to run: Add run poweshell step in Task Sequence and add task sequence variable with HP BIOSPassword, the variable name is HPIA_BIOSPassword..

    - .\ApplyHPIAOnline - OSVersion "Win10" -OSBuild "21H2" -Cleanup 
    - .\ApplyHPIAOnline - OSVersion "Win10" -OSBuild "21H2" -Cleanup -LTSC

#>

[CmdletBinding(DefaultParameterSetName = "OSBuild")]
param(
    [parameter(Mandatory=$True, HelpMessage = "Specify OS version (Win10|Win11)")]
	[string]$OSVersion,
    [parameter(Mandatory=$True, HelpMessage = "Specify Windows Build (21H2)")]
	[string]$OSBuild,
    [parameter(Mandatory = $false, HelpMessage = "Check for extra SP and INF Files in package")]
	[switch]$LTSC,
    [parameter(Mandatory = $false, HelpMessage = "Check for extra SP and INF Files in package")]
	[switch]$ExtraFilesCheck,
    [parameter(Mandatory = $false, HelpMessage = "Remove C:\HPIA when done")]
	[switch]$CleanUp
)

#Make Changes here!================================================
#$OSBuild = "21H2" #Change this to set OSBuild
#$LTSC = $True #LTSC use another standard on .cab file from HP, workaround is to rename *.cab in repository to *.e.cab, set to $false if not LTSC
#================================================================

# Construct TSEnvironment object
try {
    $TSEnvironment = New-Object -ComObject Microsoft.SMS.TSEnvironment -ErrorAction Stop
}
catch [System.Exception] {
    Write-Warning -Message "Unable to construct Microsoft.SMS.TSEnvironment object" ; exit 3
}

# Variables
$ScriptVersion = "1.0"
$HPIAPath = "C:\HPIA"
$HPCMLLogFile = "$HPIAPath" + "\" + "HPCMLInstall.log"
$HPIALogFile = $HPIAPath + "\"
$SoftpaqDownloadFolder = "$HPIAPath"

# Get TS variable
$LogFile = $TSEnvironment.Value("_SMSTSLogPath") + "\ApplyHPIAOnline.log" # ApplyHPIA log location 
$BIOSPassword = $TSEnvironment.Value("HPIA_BIOSPassword")

# Clear task sequence variable for HP Password.
$TSEnvironment.Value("HPIA_BIOSPassword") = [System.String]::Empty

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

Log -Message "ApplyHPIAOnline is about to start..." -type 1 -Component "HPIA" -LogFile $LogFile
Log -Message "Loading script with version: $Scriptversion" -type 1 -Component "HPIA" -LogFile $LogFile

[System.Environment]::SetEnvironmentVariable('biospass',"$BIOSPassword") #Set BIOS Password as environment variable, will be cleared on last line in script.

$Baseboard = (Get-CimInstance -ClassName win32_baseboard).Product
$Computersystem = (Get-CimInstance -ClassName win32_computersystem).Model

#Setup LOCALAPPDATA Variable
[System.Environment]::SetEnvironmentVariable('LOCALAPPDATA',"$env:SystemDrive\Windows\system32\config\systemprofile\AppData\Local")

$WorkingDir = $env:TEMP

#PowerShellGet from PSGallery URL
if (!(Get-Module -Name PowerShellGet)){
    $PowerShellGetURL = "https://psg-prod-eastus.azureedge.net/packages/powershellget.2.2.5.nupkg"
    Invoke-WebRequest -UseBasicParsing -Uri $PowerShellGetURL -OutFile "$WorkingDir\powershellget.2.2.5.zip"
    $Null = New-Item -Path "$WorkingDir\2.2.5" -ItemType Directory -Force
    Expand-Archive -Path "$WorkingDir\powershellget.2.2.5.zip" -DestinationPath "$WorkingDir\2.2.5"
    $Null = New-Item -Path "$env:ProgramFiles\WindowsPowerShell\Modules\PowerShellGet" -ItemType Directory -ErrorAction SilentlyContinue
    Move-Item -Path "$WorkingDir\2.2.5" -Destination "$env:ProgramFiles\WindowsPowerShell\Modules\PowerShellGet\2.2.5"
    }

#PackageManagement from PSGallery URL
if (!(Get-Module -Name PackageManagement)){
    $PackageManagementURL = "https://psg-prod-eastus.azureedge.net/packages/packagemanagement.1.4.7.nupkg"
    Invoke-WebRequest -UseBasicParsing -Uri $PackageManagementURL -OutFile "$WorkingDir\packagemanagement.1.4.7.zip"
    $Null = New-Item -Path "$WorkingDir\1.4.7" -ItemType Directory -Force
    Expand-Archive -Path "$WorkingDir\packagemanagement.1.4.7.zip" -DestinationPath "$WorkingDir\1.4.7"
    $Null = New-Item -Path "$env:ProgramFiles\WindowsPowerShell\Modules\PackageManagement" -ItemType Directory -ErrorAction SilentlyContinue
    Move-Item -Path "$WorkingDir\1.4.7" -Destination "$env:ProgramFiles\WindowsPowerShell\Modules\PackageManagement\1.4.7"
    }

#Import PowerShellGet
Import-Module PowerShellGet

#Install Module HPCMSL from PSGallery
$ModuleName = "HPCMSL"
Install-Module -Name $ModuleName -Force -AcceptLicense -SkipPublisherCheck
Import-Module -Name $ModuleName -Force

#$ModuleName = "HPCMSL"
Log -Message "Creating HPIA Folder: $HPIAPath" -type 1 -Component "HPIA" -LogFile $LogFile
New-Item -ItemType Directory -Path $HPIAPath -ErrorAction Silentlycontinue
Log -Message " - Successfully created folder: $HPIAPath" -type 1 -Component "HPIA" -LogFile $LogFile

Log -Message "----- Starting Remediation for Module $ModuleName -----" -Type 2 -LogFile $LogFile
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 # Force Powershell to use TLS1.2
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
    Log -Message "$ModuleName already Installed with $($Status.Version)" -Type 1 -LogFile $LogFile
    }

#$HPIAPath = "C:\HPIA\"
Set-Location -Path $HPIAPath

Install-HPImageAssistant -Extract -DestinationPath "C:\HPIA" -ErrorAction stop
    if (Test-Path "$HPIAPath\HPImageAssistant.exe")
    {
        Write-Output "HPIA Downloaded and installed"
        Log -Message "HPIA Downloaded and installed" -Type 1 -LogFile $LogFile
    }
    else
    {
        Write-Output "HPIA install Failed"
        Log -Message "HPIA install Failed" -Type 1 -LogFile $LogFile
        Exit 404
    }

        if (Test-Path "$HPIAPath\Repository")
        {
            Set-Location -Path "$HPIAPath\Repository"
            Initialize-Repository
        }
        else
        {
            New-Item -ItemType Directory -Path "$HPIAPath\Repository" -ErrorAction Stop
            Set-Location -Path "$HPIAPath\Repository"
            Initialize-Repository
        }
        
Add-RepositoryFilter -platform $Baseboard -os "$OSVersion"-osver $OSBuild -category dock
Log -Message "Applying repository filter to $Computersystem repository to download: Dock" -type 1 -LogFile $LogFile -Component HPIA

Add-RepositoryFilter -platform $Baseboard -os "$OSVersion"-osver $OSBuild -category driver
Log -Message "Applying repository filter to $Computersystem repository to download: Driver" -type 1 -LogFile $LogFile -Component HPIA

Add-RepositoryFilter -platform $Baseboard -os "$OSVersion"-osver $OSBuild -category firmware
Log -Message "Applying repository filter to $Computersystem repository to download: Firmware" -type 1 -LogFile $LogFile -Component HPIA

Add-RepositoryFilter -platform $Baseboard -os "$OSVersion"-osver $OSBuild -category bios
Log -Message "Applying repository filter to $Computersystem repository to download: BIOS" -type 1 -LogFile $LogFile -Component HPIA

Log -Message "Invoking repository sync for $Computersystem $Baseboard. OS: "$OSVersion", $OSBuild" -LogFile $LogFile -Component HPIA
Write-Output "Invoking repository sync for $Computersystem $Baseboard. OS: "$OSVersion", $OSBuild (might take some time)"
    
    try
    {
        Set-RepositoryConfiguration -Setting OfflineCacheMode -CacheValue Enable
        Start-Sleep -s 15
        Invoke-RepositorySync -Quiet


        Log -Message "Repository sync for $Computersystem $Baseboard. OS: $OSVerion, $OSBuild successful" -LogFile $LogFile -Component HPIA
        Write-Output "Repository sync for $Computersystem $Baseboard. OS: $OSVerion, $OSBuild successful"
    }
    catch
    {
        Log -Message "Repository sync for $Computersystem $Baseboard. OS: $OSVerion, $OSBuild NOT successful" -LogFile $LogFile -Component HPIA -Type 2
        Write-Output "Repository sync for $Computersystem $Baseboard. OS: $OSVerion, $OSBuild NOT successful"
        Log -Message "Error code: $($_.Exception.Message)" -Type 3 -Component "Error" -LogFile $LogFile
        Exit 1 # La till Exit code här behövs det?!

    }
Start-Sleep -s 15

If(-not $LTSC){
$CabName = (Get-ItemProperty $HPIAPath\Repository\.repository\cache\*.cab).name
$CabNewName = ((Get-ItemProperty $HPIAPath\Repository\.repository\cache\*.cab).name).Replace(".cab", ".e.cab")
Rename-Item -path "$HPIAPath\Repository\.repository\cache\$CabName" -newname $CabNewName
}


Set-Location "$HPIAPath\"
        [System.Environment]::SetEnvironmentVariable("biospass","$($BIOSPassword)")
        $Argument = "/Operation:Analyze /Action:install /Selection:All /OfflineMode:Repository /noninteractive /Debug /SoftpaqDownloadFolder:$($SoftpaqDownloadFolder) /ReportFolder:$($HPIALogFile) /BIOSPwdEnv:biospass"              


        # Start HPIA Update process 
        Log -Message "Starting HPIA installation." -type 1 -Component "HPIA" -LogFile $LogFile
        $HPIAProcess = Start-Process -Wait -FilePath "HPImageAssistant.exe" -WorkingDirectory $SoftpaqDownloadFolder -ArgumentList "$Argument" -PassThru
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
        
            Log -Message "Install Reboot Required SoftPaq installations are successful, and at least one requires a reboot" -Component "HPIA" -Type 1 -logfile $LogFile

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

[System.Environment]::SetEnvironmentVariable('biospass','Secret')

Log -Message "HPIA script is now completed." -Component "HPIA" -Type 1 -logfile $LogFile
Log -Message "---------------------------------------------------------------------------------------------------------------------------------------------------" -type 1 -Component "HPIA" -LogFile $LogFile
