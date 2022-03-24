<# Author: Daniel Grahns, Nicklas Eriksson
 
  Purpose: Download HP Drivers to a repository and apply drivers with ConfigMgr adminservice and a custom script in the taskSequence. Check out ApplyHPIA.ps1 how to apply the drivers during OSD or IPU.
  Information: Some variabels are hardcoded, search on Hardcoded variabels and you will find those. 
  Link to project: https://github.com/EGGLAS/ConfigMgr
  Created: 2021-02-11
  Latest updated: 2022-03-22
  Current version: 2.0

  Changelog: 1.0 - 2021-02-11 - Nicklas Eriksson -  Script Edited and fixed Daniels crappy hack and slash code :)
             1.1 - 2021-02-18 - Nicklas Eriksson - Added HPIA to download to HPIA Download instead to Root Directory, Added BIOSPwd should be copy to HPIA so BIOS upgrades can be run during OSD. 
             1.2 - 2021-04-14 - Daniel Grahns - Added check if Offline folder is created
             1.3 - 2021-04-27 - Nicklas Eriksson - Completed the function so the script also downloaded BIOS updates during sync.
             1.4 - 2021-05-21 - Nicklas Eriksson & Daniel GrÃ¥hns - Changed the logic for how to check if the latest HPIA is downloaded or not since HP changed the how the set the name for HPIA.
             1.5 - 2021-06-10 - Nicklas Eriksson - Added check to see that folder path exists in ConfigMgr otherwise creat the folder path.
             1.6 - 2021-06-17 - Nicklas Eriksson - Added -Quiet to Invoke-RepositorySync, added max log size so the log file will rollover.
             1.7 - 2021-06-18 - Nicklas Eriksson & Daniel GrÃ¥hns - Added if it's the first time the model is running skip filewatch.
             1.8 - 2022-02-01 - Daniel Grahns and Rickard Lundberg 
                                 - Updated Roboycopy syntax
                                 - Check if PSDrive exists for ConfigMgr if not it will be mapped.
             1.9 - 2022-02-09 - Modified by Marcus Wahlstam, Advitum AB <marcus.wahlstam@advitum.se>
                                - Fancier console output (see Print function)
                                - Updated Config XML with more correct settings names
                                - Removed unused code
                                - Windows 11 support
                                - Changed folder structure of the repository, both disk level and in CM (to support both Windows 10 and 11 and to make repository cleaner)
                                - Added migration check - will migrate old structure to the new structure (both disk level and CM)
                                - Changed how repository filters are handled in the script
                                - Added function to check if module is updated or not before trying to update it
                                - Fixed broken check if HPIA was updated or not (will now check value of FileVersionInfo.FileVersion on HPImageassistant.exe)
                                - Changed csv format of supported models, added column "WindowsVersion" (set to Win10 or Win11)
                                - Changed format of package name to include WindowsVersion (Win10 or Win11)
                                - Offline cache folder is now checked 10 times if it exists (while loop)
                                - Added progress bar to show which model is currently processed and how many there are left
             2.0 - 2022-03-22 - Nicklas Eriksson and Daniel Grahns
                                - Added Register-PSRepo to be done automatic if modules fails to download from PSGallery.
                                - Made Migration to new structure optional and which OS you want to migrate to new folder structure (Use this only if you have Windows 10 as only OS and not started with Windows 11 since the old naming structure did not contain OS Version.)
                                - Removed unused code
                                - Added more logging to the log
                                - Added more error handling to the script to be able to catch errors to the log file.
 
 Contact: Grahns.Daniel@outlook.com, erikssonnicklas@hotmail.com
 Twitter: Sigge_gooner 
 LinkedIn: https://www.linkedin.com/in/danielgrahns/
           https://www.linkedin.com/in/nicklas-sigge-eriksson
 Facebook: https://www.facebook.com/daniel.grahns/
 
 TO-Do
 - Maybe add support for Software.
 - More error handling
 - Add function to remove old package and sources files if the model is no longer supported.

 How to run HPIA:
    - ImportHPIA.ps1 -Config .\Config.xml

 Credit, inspiration and copy/paste code from: garytown.com, dotnet-helpers.com, ConfigMgr.com, www.imab.dk, Ryan Engstrom

 You running this script/function means you will not blame the author(s) if this breaks your stuff. This script/function is provided AS IS without warranty of any kind. The entire risk arising out of the use or performance of the sample scripts and documentation remains with you. 
 In no event shall author(s) be held liable for any damages whatsoever (including, without limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary loss) arising out of the use of or inability to use the script or documentation. 
 Simply put: Use at your own risk.

#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage='Path to XML Configuration File')]
    [string]$Config
)

#$Config = "E:\scripts\importhpia\Config.xml" #(.\ImportHPIA.ps1 -config .\config.xml) # Only used for debug purpose, it's better to run the script from script line.
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

function Print
{
    param(
    [Parameter(Mandatory=$true)]
    [string]$Message,
    [Parameter(Mandatory=$false)]
    [string]$Color = "White",
    [Parameter(Mandatory=$false)]
    [int]$Indent
    )

    switch ($Indent)
    {
        1 {$Prefix = "  "}
        2 {$Prefix = "     "}
        3 {$Prefix = "        "}
        4 {$Prefix = "           "}
        5 {$Prefix = "             "}
        6 {$Prefix = "               "}
        default {$Prefix = " "}
    }

    $DateTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$DateTime - $Prefix$Message" -ForegroundColor $Color 
}

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


function ModuleUpdateAvailable($Module)
{
    [version]$OnlineVersion = (Find-Module $Module).Version
    [version]$InstalledVersion = (Get-Module -ListAvailable | where {$_.Name -eq "$Module"} -ErrorAction Ignore | sort Version -Descending).Version | select -First 1

    if ($OnlineVersion -le $InstalledVersion)
    {
        return $false
    }
    else
    {
        return $true
    }
}

Print -Message "######################################" -Color Cyan
Print -Message "### MASHPIA - Starting Import-HPIA ###" -Color Cyan
Print -Message "######################################" -Color Cyan

Print -Message "Initializing script" -Color Magenta

if (Test-Path -Path $Config) {
 
    $Xml = [xml](Get-Content -Path $Config -Encoding UTF8)
    Print -Message "Successfully loaded config file: $Config" -Indent 1 -Color Green

 }
 else {
    
    $ErrorMessage = $_.Exception.Message
    Print -Message "Could not find config file: $Config" -Indent 1 -Color Red
    Print -Message "Error: $ErrorMessage" -Indent 1 -Color Red
    Exit 1

 }
 
# Getting information from Config File
$InstallPath = $Xml.Configuration.Install | Where-Object {$_.Name -like 'InstallPath'} | Select-Object -ExpandProperty "Value"
$XMLInstallHPIA = $Xml.Configuration.Install | Where-Object {$_.Name -like 'InstallHPIA'} | Select-Object 'Enabled','Value'
$RepositoryPath = $Xml.Configuration.Install | Where-Object {$_.Name -like 'RepositoryPath'} | Select-Object -ExpandProperty 'Value'
$ConfigMgrModule = $Xml.Configuration.Install | Where-Object {$_.Name -like 'ConfigMgrModule'} | Select-Object -ExpandProperty 'Value'
$SupportedModelsCSV = $Xml.Configuration.Install | Where-Object {$_.Name -like 'SupportComputerModels'} | Select-Object -ExpandProperty 'Value'
$SiteCode = $Xml.Configuration.Setting | Where-Object {$_.Name -like 'SiteCode'} | Select-Object -ExpandProperty 'Value'
$SiteServer = $Xml.Configuration.Setting | Where-Object {$_.Name -like 'SiteServer'} | Select-Object -ExpandProperty 'Value'
$CMFolderPath = $Xml.Configuration.Setting | Where-Object {$_.Name -like 'CMFolderPath'} | Select-Object -ExpandProperty 'Value'
$DPGroupName = $Xml.Configuration.Setting | Where-Object {$_.Name -like 'DPGroupName'} | Select-Object -ExpandProperty 'Value'
$HPIAFilter_Dock = $Xml.Configuration.HPIAFilter | Where-Object {$_.Name -like 'Dock'} | Select-Object -ExpandProperty 'Enabled'
$HPIAFilter_Driver = $Xml.Configuration.HPIAFilter | Where-Object {$_.Name -like 'Driver'} | Select-Object -ExpandProperty 'Enabled'
$HPIAFilter_Firmware = $Xml.Configuration.HPIAFilter | Where-Object {$_.Name -like 'Firmware'} | Select-Object -ExpandProperty 'Enabled'
$HPIAFilter_Driverpack = $Xml.Configuration.HPIAFilter | Where-Object {$_.Name -like 'Driverpack'} | Select-Object -ExpandProperty 'Enabled'
$HPIAFilter_BIOS = $Xml.Configuration.HPIAFilter | Where-Object {$_.Name -like 'BIOS'} | Select-Object -ExpandProperty 'Enabled'
$InstallHPCML = $Xml.Configuration.Option | Where-Object {$_.Name -like 'InstallHPCML'} | Select-Object -ExpandProperty 'Enabled'
$MigratePaths = $Xml.Configuration.Option | Where-Object {$_.Name -like 'MigratePaths'} | Select-Object -ExpandProperty 'Enabled'
$MigratePathsOS = $Xml.Configuration.Option | Where-Object {$_.Name -like 'MigratePaths'} | Select-Object -ExpandProperty 'Value'
$XMLEnableSMTP = $Xml.Configuration.Option | Where-Object {$_.Name -like 'EnableSMTP'} | Select-Object 'Enabled','SMTP',"Adress"
#$XMLLogfile = $Xml.Configuration.Option | Where-Object {$_.Name -like 'Logfile'} | Select-Object -ExpandProperty 'Value'

# Hardcoded variabels in the script.
$ScriptVersion = "2.0"
$LogFile = "$InstallPath\RepositoryUpdate.log" #Filename for the logfile.
[int]$MaxLogSize = 9999999


#If the log file exists and is larger then the maximum then roll it over with with an move function, the old log file name will be .lo_ after.
If (Test-path  $LogFile -PathType Leaf) {
    If ((Get-Item $LogFile).length -gt $MaxLogSize){
        Move-Item -Force $LogFile ($LogFile -replace ".$","_")
        Log -Message "The old log file is too big, renaming it and creating a new logfile" -LogFile $Logfile

    }
}

Log  -Message  "<--------------------------------------------------------------------------------------------------------------------->"  -type 2 -LogFile $LogFile
Log -Message "Successfully loaded ConfigFile from $Config" -LogFile $Logfile
Log -Message "Script was started with version: $($ScriptVersion)" -type 1 -LogFile $LogFile

# This will migrate all files and all packages to new folder structure!!
if ($MigratePaths -eq "True")
{
    # Check if there is anything to migrate from old to new structure with support for Windows 11
    $NewFolderStructureTest = Get-ChildItem $RepositoryPath | where {$_.Name -eq "Win10" -or $_.Name -eq "Win11"}
    $OldFolderNames = "$MigratePathsOS" #remove those you dont want to migrate
    $OldFolderNames = [array]($OldFolderNames -split ",")
    $OldFolderTest = Get-ChildItem $RepositoryPath | where {$_.Name -in $OldFolderNames}
    

    if (([string]::IsNullOrEmpty($NewFolderStructureTest)) -or (-not [string]::IsNullOrEmpty($OldFolderTest))) 
    {
        Print -Message "Need to migrate following OS builds to the new folder structure: $OldFolderTest" -Color Yellow -Indent 1
        Log -Message "Need to migrate following OS builds to the new folder structure: $OldFolderTest" -type 2 -Component "LogFile" -LogFile $LogFile    
        
        Print -Message "New folder structure does not exist, need to migrate and rename packages to new structure" -Color Yellow -Indent 1
        Log -Message " - New folder structure does not exist, need to migrate and rename packages to new structure" -type 2 -Component "LogFile" -LogFile $LogFile    
        
        try
        {
            Log -Message "Importing ConfigMgr Module from $ConfigMgrModule" -type 2 -Component "LogFile" -LogFile $LogFile    
            Import-Module $ConfigMgrModule

        }
        catch 
        {
            Log -Message "Failed to import ConfigMgr Module from $ConfigMgrModule" -Type 3 -Component "Error" -LogFile $LogFile
            Log -Message "Error code: $($_.Exception.Message)" -type 3 -Component "Script" -LogFile $LogFile
            exit 1
        }
        
        # Customizations
        $initParams = @{}

        # Connect to the site's drive if it is not already present
        if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
            New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $SiteServer @initParams
            Log -Message "Mapping PSDrive for ConfigMgr" -type 1 -LogFile $LogFile -Component ConfigMgr

        }
        #Set-location "$($SiteCode):\"
        Set-Location $InstallPath

        # Moving repository to new structure, assuming old is Windows 10
        Print -Message "Assuming old folder structure is for Windows 10, creating Win10 subfolder in $RepositoryPath" -Color Green -Indent 2
        Log -Message " - Assuming old folder structure is for Windows 10, creating Win10 subfolder in $RepositoryPath" -type 2 -Component "LogFile" -LogFile $LogFile    
        $OldFolders = Get-ChildItem $RepositoryPath | where {$_.Name -in $OldFolderNames}
        $NewWin10Folder = New-Item $(Join-Path $RepositoryPath "Win10") -ItemType Directory -ErrorAction SilentlyContinue
        
        if ((Test-Path -Path "$RepositoryPath\win10") -eq $True) # Needed to add this if Win10 folder already exists the variable $NewWin10Folder will be empty.
        {
            $NewWin10Folder = "$RepositoryPath\win10"
        }

        foreach ($OldFolder in $OldFolders)
        {
            Print -Message "Working on $($OldFolder.FullName)" -Color Green -Indent 3
            Log -Message "  - Working on $($OldFolder.FullName)" -type 1 -Component "LogFile" -LogFile $LogFile    
            Set-Location $InstallPath
            Set-Location "$RepositoryPath"
            Print -Message "Moving $($OldFolder.FullName) to $($NewWin10Folder.FullName)" -Color Green -Indent 4
            Move-Item $OldFolder $NewWin10Folder -Force

            # ConfigMgr changes
            Print -Message "Creating new package root folder in ConfigMgr" -Color Green -Indent 4
            Log -Message "  - Creating new package root folder in ConfigMgr" -type 1 -Component "LogFile" -LogFile $LogFile    

            Set-location "$($SiteCode):\"
            $NewCMRootPath = New-Item -ItemType Directory "$CMfolderPath\Win10"
            $NewCMParentPath = New-Item -ItemType Directory "$CMfolderPath\Win10\$($OldFolder.Name)"
            $NewCMParentPath = "$CMfolderPath\Win10\$($OldFolder.Name)"
            Set-Location $InstallPath
            Set-Location $RepositoryPath

            $SourcePackages = Get-ChildItem $(Join-Path $NewWin10Folder $OldFolder)

            foreach ($SourcePackage in $SourcePackages)
            {
                $SourcePackageName = $SourcePackage.Name
                Print -Message "Working on ($($SourcePackage.Name))" -Color Green -Indent 5
                Log -Message " - Working on ($($SourcePackage.Name))" -type 1 -Component "LogFile" -LogFile $LogFile    

                Set-location "$($SiteCode):\"                
                $CMPackage = Get-CMPackage -Name "*$SourcePackageName" -Fast | Where-Object Name -like "HPIA-$($OldFolder.Name)-*" | Select Name, PackageID                            

                if (-not ([string]::IsNullOrEmpty($CMPackage)))
                {
                    Print -Message "Setting new sourcepath ($($SourcePackage.FullName)) in ConfigMgr for package $($CMPackage.Name)" -Color Green -Indent 6
                    Log -Message "  - Setting new sourcepath ($($SourcePackage.FullName)) in ConfigMgr for package $($CMPackage.Name)" -type 1 -Component "LogFile" -LogFile $LogFile    
                    Set-CMPackage -Name $($CMPackage.Name) -Path $($SourcePackage.FullName)
                
                    $NewCMPackageName = $($CMPackage.Name) -replace 'HPIA-','HPIA-Win10-'
                    Print -Message "Renaming package $($CMPackage.Name) to $NewCMPackageName" -Color Green -Indent 6
                    Log -Message "  - Renaming package $($CMPackage.Name) to $NewCMPackageName" -type 1 -Component "LogFile" -LogFile $LogFile    
                    Set-CMPackage -Name $($CMPackage.Name) -NewName $NewCMPackageName

                    Print -Message "Moving package $NewCMPackageName to $NewCMParentPath" -Color Green -Indent 6
                    Log -Message "  - Moving package $NewCMPackageName to $NewCMParentPath" -type 1 -Component "LogFile" -LogFile $LogFile    
                    Move-CMObject -FolderPath $NewCMParentPath -ObjectId $CMPackage.PackageID
                }
                else
                {
                    # Could not find CMPackage based on folder name
                    Print -Message "Could not find package based on folder name ($SourcePackageName)" -Color Red -Indent 4
                    Log -Message " - Could not find package based on folder name ($SourcePackageName)" -type 3 -Component "LogFile" -LogFile $LogFile    
                }
            }
        }
        Set-Location $InstallPath
        Print -Message "Done migrating packages" -Color Green -Indent 1
        Log -Message "Done migrating packages" -type 3 -Component "LogFile" -LogFile $LogFile    
    }
    else
    {
       # New folder structure in place 
    }
}

# CHeck if HPCMSL should autoupdate from Powershell gallery if's specified in the config.
if ($InstallHPCML -eq "True")
{
        Log -Message "HPCML was enabled to autoinstall in ConfigFile, starting to install HPCML" -type 1 -LogFile $LogFile
        Print -Message "Installation of HPCML was enabled in config. Installing HPCML" -Indent 1 -Color Green
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 # Force Powershell to use TLS1.2
        # make sure Package NuGet is up to date 
        Print -Message "Checking if there's a new version of PowerShellGet module" -Indent 1
        Log -Message "Checking if there's a new version of PowerShellGet module" -type 1 -Component "LogFile" -LogFile $LogFile    

        if (ModuleUpdateAvailable -Module "PowerShellGet")
        {
            Print -Message "New version of PowerShellGet module found, installing" -Indent 2
            Log -Message "New version of PowerShellGet module found, installing" -type 1 -Component "LogFile" -LogFile $LogFile    

            try
            {
                Install-Module -Name PowerShellGet -Force -ErrorAction Stop  # install the latest version of PowerSHellGet module
                Update-Module -Name PowerShellGet -ErrorAction Stop 
                Log -Message "Successfully installed PowershellGet from PSRepo" -type 1 -Component "LogFile" -LogFile $LogFile    
            }
            catch 
            {
                Log -Message "Running Register-PSRepository" -Type 3 -Component "Error" -LogFile $LogFile
                Register-PSRepository -Default -Verbose -ErrorAction Stop 
                Log -Message "Please close all open Powershell windows and restart Powershell" -Type 3 -Component "Error" -LogFile $LogFile
                Log -Message " - Error code: $($_.Exception.Message)" -Type 3 -Component "Error" -LogFile $LogFile
                Exit 1
            }
    
        }
        else
        {
            Print -Message "No newer version of PowerShellGet module found, importing module" -Indent 2
            Log -Message "No newer version of PowerShellGet module found, importing module" -Type 1 -Component "LogFile" -LogFile $LogFile
            try
            {
                Import-Module PowerShellGet -ErrorAction Stop
            }
            catch 
            {
                Log -Message "Could not import PowerShellGet Module" -Type 3 -Component "Error" -LogFile $LogFile
                Log -Message " - Error code: $($_.Exception.Message)" -Type 3 -Component "Error" -LogFile $LogFile
                Exit 1
            }
        }

        Print -Message "Checking if there's a new version of HPCMSL module" -Indent 1
        Log -Message "Checking if there's a new version of HPCMSL module" -Type 1 -Component "LogFile" -LogFile $LogFile

        if (ModuleUpdateAvailable -Module "HPCMSL")
        {
            try
            {
                Print -Message "New version of HPCMSL module found, installing" -Indent 2
                Log -Message "New version of HPCMSL module found, installing" -Type 1 -Component "LogFile" -LogFile $LogFile

                Install-Module -Name HPCMSL -Force -AcceptLicense -Scope AllUsers

            }
            catch 
            {
                Log -Message "Could not import HPCMSL Module" -Type 3 -Component "Error" -LogFile $LogFile
                Log -Message " - Error code: $($_.Exception.Message)" -Type 3 -Component "Error" -LogFile $LogFile
                Exit 1
            }
        }
        else
        {
            Print -Message "No newer version of HPCMSL module found, importing module" -Indent 2
            Log -Message "No newer version of HPCMSL module found, importing module" -Type 1 -Component "LogFile" -LogFile $LogFile

            Import-Module HPCMSL
        }
        Log -Message "HPCML was successfully updated" -type 1 -LogFile $LogFile -Component HPIA

}
else
{
    Log -Message "HPCML was not enabled to autoinstall/update from Powershell Gallery in ConfigFile" -type 1 -LogFile $LogFile -Component HPIA
    Print -Message "Installation/update of HPCML was disabled in config. Skipping." -Indent 1 -Color Green
}

Print -Message "Checking HPIA Prereqs" -Color Magenta
Log -Message "Checking HPIA Prereqs" -type 1 -LogFile $LogFile -Component HPIA

# Check if HPIA Installer was updated and create download folder for HPIA. With this folder we control if any new versions of HPIA is downloaded.
if ((Test-path -Path "$($XMLInstallHPIA.Value)\HPIA Download") -eq $false)
{
    Log -Message "HPIA Download folder does not exists" -type 1 -LogFile $LogFile -Component HPIA
    Log -Message "Creating HPIA Download folder" -type 1 -LogFile $LogFile -Component HPIA

    Print -Message "HPIA Download folder does not exist, creating it." -Color Green -Indent 1
    New-Item -ItemType Directory -Path "$($XMLInstallHPIA.Value)\HPIA Download" -ErrorAction Stop
    Print -Message "Creating information file" -Color Green -Indent 1
    New-Item -ItemType File -Path "$($XMLInstallHPIA.Value)\HPIA Download\Dont Delete the latest SP-file.txt" -ErrorAction Stop
    Log -Message "Creating file, dont delete the latest SP-file.txt" -type 1 -LogFile $LogFile -Component HPIA

}
else
{
    Log -Message "HPIA Download folder exists, no need to create folder" -type 1 -LogFile $LogFile -Component HPIA
    Print -Message "HPIA Download folder exists. Skipping." -Color Green -Indent 1
}

Print -Message "Processing HPIA Tasks" -Color Magenta
Log -Message "Processing HPIA Tasks" -type 1 -LogFile $LogFile -Component HPIA

[version]$CurrentHPIAVersion = (Get-Command "$($XMLInstallHPIA.Value)\HPIA Base\HPImageAssistant.exe").FileVersionInfo.FileVersion

Print -Message "Updating HPIA Files" -Color Green -Indent 1
Log -Message "Updating HPIA Files" -type 1 -LogFile $LogFile -Component HPIA

# CHeck if HPIA should autoupdate from HP if's specified in the config.
if ($XMLInstallHPIA.Enabled -eq "True")
{
        Log -Message "HPIA was enabled to autoinstall in ConfigFile, starting to autoupdate HPIA" -type 1 -LogFile $LogFile -Component HPIA
        Print -Message "Running HPIA Install" -Color Green -Indent 2
        Set-location -Path "$($XMLInstallHPIA.Value)\HPIA Download"
        try
        {
            Install-HPImageAssistant -Extract -DestinationPath "$($XMLInstallHPIA.Value)\HPIA Base" -ErrorAction Stop
            Set-Location -path $InstallPath
            Log -Message "HPIA was successfully updated in $($XMLInstallHPIA.Value)\HPIA Base" -type 1 -LogFile $LogFile -Component HPIA
            Print -Message "HPIA was successfully updated in $($XMLInstallHPIA.Value)\HPIA Base" -Color Green -Indent 2
        }
        catch
        {
            Print -Message "Error: HPIA could not be updated" -Color Red -Indent 2
            Log -Message "Error: HPIA could not be updated" -Type 3 -Component "Error" -LogFile $LogFile
            Log -Message "Error code: $($_.Exception.Message)" -Type 3 -Component "Error" -LogFile $LogFile
        }                
}
else
{
    Print -Message "HPIA update is disabled in config" -Color Green -Indent 2
    Log -Message "HPIA was not enabled to autoinstall in ConfigFile" -type 1 -LogFile $LogFile   
}

Print -Message "Processing BIOS password file" -Color Green -Indent 1
Log -Message "Processing BIOS password file" -type 1 -LogFile $LogFile -Component HPIA

# Copy BIOS PWD to HPIA. 
$BIOS = (Get-ChildItem -Path "$($XMLInstallHPIA.Value)\*.bin" | sort LastWriteTime -Descending | select -First 1) # Check for any Password.BIN file. 

if (-not ([string]::IsNullOrEmpty($BIOS)))
{
    if (Test-Path $BIOS.FullName)
    {
        Print -Message "Found BIOS password file: $($BIOS.Fullname)" -Color Green -Indent 2
        Log -Message "Found BIOS password file: $($BIOS.Fullname)" -type 1 -LogFile $LogFile -Component HPIA

        if (-not (Test-Path -Path "$($XMLInstallHPIA.Value)\HPIA Base\$($BIOS.Name)")) {
            Print -Message "BIOS Password file not found in $($XMLInstallHPIA.Value)\HPIA Base, copying." -Color Green -Indent 2
            Log -Message "BIOS Password file not found in $($XMLInstallHPIA.Value)\HPIA Base, copying" -type 1 -LogFile $LogFile -Component HPIA
            Copy-Item -Path $BIOS -Destination "$($XMLInstallHPIA.Value)\HPIA Base"
        } 
        else {
            Log -Message "BIOS File exists in HPIA or does not exits in root, no need to copy" -type 1 -LogFile $LogFile -Component HPIA
            Print -Message "BIOS File exists in HPIA, no need to copy" -Color Green -Indent 2
        }
    }
}

# If HPIA Installer was not updated, set false flag value
[version]$NewHPIAVersion = (Get-Command "$($XMLInstallHPIA.Value)\HPIA Base\HPImageAssistant.exe").FileVersionInfo.FileVersion

Print -Message "Checking if HPIA was updated" -Color Green -Indent 1
Log -Message "Checking if HPIA was updated" -type 1 -LogFile $LogFile -Component HPIA

if($CurrentHPIAVersion -le $NewHPIAVersion) {
    $HPIAVersionUpdated = $false
    Print -Message "HPIA was not updated, will not copy HPIA to existing driverpackages" -Color Green -Indent 2
    Log -Message "HPIA was not updated, skipping to set HPIA to copy to driverpackages" -type 1 -LogFile $LogFile -Component HPIA
} 
else {
    $HPIAVersionUpdated = $true

    Print -Message "HPIA was updated, will copy HPIA to existing driverpackages" -Color Green -Indent 2
    Log -Message "HPIA was updated will update HPIA in each Driverpackage" -type 1 -LogFile $LogFile -Component HPIA
    }

# Check if Email notificaiton is enabled in the config.
if ($XMLEnableSMTP.Enabled -eq "True") {
    $SMTP = $($XMLEnableSMTP.SMTP)
    $EMAIL = $($XMLEnableSMTP.Adress)
    Log -Message "Added SMTP: $SMTP and EMAIL: $EMAIL" -type 1 -LogFile $LogFile -Component HPIA
} 
else {
    Log -Message "Email notification is not enabled in the Config" -type 1 -LogFile $LogFile -Component HPIA
}

Print -Message "Processing models and drivers" -Color Magenta
Log -Message "Processing models and drivers" -type 1 -LogFile $LogFile -Component HPIA
Log -Message "Importing CSV with supported models" -type 1 -LogFile $LogFile -Component HPIA

Print -Message "Importing CSV with supported models" -Color Green -Indent 1

#Importing supported computer models CSV file
if (Test-path $SupportedModelsCSV) {
	$ModelsToImport = Import-Csv -Path $SupportedModelsCSV -ErrorAction Stop
    if ($ModelsToImport.Model.Count -gt "1")
    {
        Log -Message "Info: $($ModelsToImport.Model.Count) models found" -Type 1 -LogFile $LogFile -Component FileImport
        Print -Message "$($ModelsToImport.Model.Count) models found" -Color Green -Indent 2

    }
    else
    {
        Log -Message "Info: $($ModelsToImport.Model.Count) model found" -Type 1 -LogFile $LogFile -Component FileImport
        Print -Message "$($ModelsToImport.Model.Count) model found" -Color Green -Indent 2

    }   
}
else {
    Print -Message "Could not find any .CSV file, the script will break" -Color Red -Indent 2
    Log -Message "Could not find any .CSV file, the script will break" -Type 3 -LogFile $LogFile -Component FileImport
    Break
}

$HPModelsTable = foreach ($Model in $ModelsToImport) {
    @(
    @{ ProdCode = "$($Model.ProductCode)"; Model = "$($Model.Model)"; WindowsBuild = $Model.WindowsBuild; WindowsVersion = $Model.WindowsVersion }
    )
    Log -Message "Added $($Model.ProductCode) $($Model.Model) $($Model.WindowsVersion) $($Model.WindowsBuild) to download list" -type 1 -LogFile $LogFile -Component FileImport
    Print -Message "Added $($Model.ProductCode) $($Model.Model) $($Model.WindowsVersion) $($Model.WindowsBuild) to download list" -Color Green -Indent 3
}

Print -Message "Processing specified models" -Color Green -Indent 1
Log -Message "Processing specified models" -type 1 -LogFile $LogFile -Component HPIA

$ModelsToImportCount = $ModelsToImport.Model.Count
$CurrentModelCount = 0

# Loop through the list of models in csv file
foreach ($Model in $HPModelsTable) {
    $CurrentModelCount++
    Write-Progress -Id 1 -Activity "Working on $($Model.Model) ($CurrentModelCount of $ModelsToImportCount)" -PercentComplete ($CurrentModelCount/$ModelsToImportCount*100)

    # Set WindowsBuild for 2009 to 20H2.  
    if($Model.WindowsBuild -eq "2009") # Want to set WindowsVersion to 20H2 in ConfigMgr, and must use 2009 to download Drivers from HP.
    {
         $WindowsBuild = "20H2"
         
    }
    else
    {
        $WindowsBuild = $Model.WindowsBuild
    }

    $GLOBAL:UpdatePackage = $False

    #==============Monitor Changes for Update Package======================================================

    Log -Message "----------------------------------------------------------------------------" -LogFile $LogFile -Component HPIA -Type 1

    Print -Message "Working on $($Model.Model)" -Color Cyan -Indent 2
    Log -Message "Working on $($Model.Model)" -type 1 -LogFile $LogFile -Component HPIA

    $ModelPath = Join-Path $RepositoryPath "$($Model.WindowsVersion)\$WindowsBuild\$($Model.Model) $($Model.ProdCode)"
    $ModelRepositoryPath = Join-Path $ModelPath "Repository"

    if (Test-path $ModelRepositoryPath)
    {
        $ModelRepositoryExists = $true
        Print -Message "$($Model.Model) exists in local repository, monitoring is needed to see if any softpaqs changes is made during repository synchronization" -Color Green -Indent 3
        Log -Message "$($Model.Model) exists, monitoring is needed to see if any softpaqs changes in the repository during the synchronization" -Type 1 -Component FileWatch -LogFile $LogFile

        $filewatcher = New-Object System.IO.FileSystemWatcher
    
        #Mention the folder to monitor
        $filewatcher.Path = $ModelRepositoryPath
        $filewatcher.Filter = "*.cva"
        #include subdirectories $true/$false
        $filewatcher.IncludeSubdirectories = $False
        $filewatcher.EnableRaisingEvents = $true  
    ### DEFINE ACTIONS AFTER AN EVENT IS DETECTED
        $writeaction = { $path = $Event.SourceEventArgs.FullPath
                    $changeType = $Event.SourceEventArgs.ChangeType
                    $logline = "$(Get-Date), $changeType, $path"
                    Print -Message "$logline" -Indent 3 -Color Green
                    Print -Message "Setting Update Package to True, need to update package on $DPGroupName when sync is done" -Indent 3 -Color Green
                    Log -Message "$logline" -Type 1 -Component FileWatch -LogFile $LogFile
                    Log -Message "Setting Update Package to True, need to update package on $DPGroupName when synchronization is done" -Type 1 -Component FileWatch -LogFile $LogFile
                    $GLOBAL:UpdatePackage = $True
                    #Write-Host "Info: Write Action $UpdatePackage"
                  }
              
    ### DECIDE WHICH EVENTS SHOULD BE WATCHED
        Register-ObjectEvent $filewatcher "Created" -Action $writeaction | Out-Null
        Register-ObjectEvent $filewatcher "Changed" -Action $writeaction | Out-Null
        Register-ObjectEvent $filewatcher "Deleted" -Action $writeaction | Out-Null
        Register-ObjectEvent $filewatcher "Renamed" -Action $writeaction | Out-Null

    }
    else
    {
        $ModelRepositoryExists = $false

        Print -Message "This is the first time syncing $($Model.Model), no need to monitor file changes" -Indent 3 -Color Green
        Log -Message "It's the first time this $($Model.Model) is running, no need to monitor file changes" -Type 1 -Component FileWatch -LogFile $LogFile

        Log -Message "Creating repository $ModelRepositoryPath" -LogFile $LogFile -Type 1 -Component HPIA
        Print -Message "Creating repository $ModelRepositoryPath" -Indent 3 -Color Green
        New-Item -ItemType Directory -Path $ModelRepositoryPath -Force | Out-Null
        
        if (Test-Path $ModelRepositoryPath)
        {
            Log -Message "$ModelRepositoryPath successfully created" -LogFile $LogFile -Type 1 -Component HPIA
            Print -Message "Repository $ModelRepositoryPath successfully created" -Indent 4 -Color Green
        }
        else
        {
            Log -Message "Failed to create repository $ModelRepositoryPath" -LogFile $LogFile -Type 3 -Component HPIA
            Print -Message "Failed to create repository $ModelRepositoryPath. Cannot continue" -Indent 4 -Color Red
            Exit
        }
    }

    $ModelRepositoryInitPath = Join-Path $ModelRepositoryPath ".repository"
    if (-not (Test-Path $ModelRepositoryInitPath))
    {
        Log -Message "Repository not initialized, initializing now" -LogFile $LogFile -Type 1 -Component HPIA
        Print -Message "Repository not initialized, initializing now" -Indent 3 -Color Green

        Set-Location -Path $ModelRepositoryPath
        
        Initialize-Repository

        if (Test-Path $ModelRepositoryInitPath)
        {
            Print -Message "Repository $($Model.Model) $($Model.ProdCode) successfully initialized" -Indent 4 -Color Green
            Log -Message "$($Model.Model) $($Model.ProdCode) repository successfully initialized" -LogFile $LogFile -Type 1 -Component HPIA
        }
        else
        {
            Log -Message "Failed to initialize repository for $($Model.Model) $($Model.ProdCode)" -LogFile $LogFile -Type 3 -Component HPIA
            Print -Message "Repository $($Model.Model) $($Model.ProdCode) failed to initialize. Cannot continue" -Indent 4 -Color Red
            Exit
        }
    }    
    
    Log -Message "Setting download location to: $ModelRepositoryPath" -LogFile $LogFile -Type 1 -Component HPIA
    Set-Location -Path $ModelRepositoryPath
    
    if ($XMLEnableSMTP.Enabled -eq "True") {
        Set-RepositoryNotificationConfiguration $SMTP
        Add-RepositorySyncFailureRecipient -to $EMAIL
        Log -Message "Configured notification for $($Model.Model) $($Model.ProdCode) with SMTP: $SMTP and Email: $EMAIL" -LogFile $LogFile -Type 1 -Component HPIA
    }  
    
    Log -Message "Remove any existing repository filter for $($Model.Model)" -LogFile $LogFile -Type 1 -Component HPIA
    Remove-RepositoryFilter -platform $($Model.ProdCode) -yes
    
    Print -Message "Applying repository filter for $($Model.Model)" -Indent 3 -Color Green
    Log -Message "Applying repository filter for $($Model.Model) repository" -LogFile $LogFile -Type 1 -Component HPIA

    # Set HPIA Filter: Dock
    if ($HPIAFilter_Dock -eq "True") {
           Add-RepositoryFilter -platform $($Model.ProdCode) -os $($Model.WindowsVersion) -osver $($Model.WindowsBuild) -category dock
           Log -Message "Applying repository filter to $($Model.Model) repository to download: Dock" -type 1 -LogFile $LogFile -Component HPIA
    }
    else {
        Log -Message "Not applying repository filter to download $($Model.Model) for: Dock" -type 1 -LogFile $LogFile -Type 1 -Component HPIA
    }

    # Set HPIA Filter: Driver
    if ($HPIAFilter_Driver -eq "True") {
        Add-RepositoryFilter -platform $($Model.ProdCode) -os $($Model.WindowsVersion) -osver $($Model.WindowsBuild) -category driver
        Log -Message "Applying repository filter to $($Model.Model) repository to download: Driver" -type 1 -LogFile $LogFile -Component HPIA
    }
    else {
        Log -Message "Not applying repository filter to download $($Model.Model) for: Driver" -type 1 -LogFile $LogFile -Component HPIA
    }

    # Set HPIA Filter: Firmware
    if ($HPIAFilter_Firmware -eq "True") {
        Add-RepositoryFilter -platform $($Model.ProdCode) -os $($Model.WindowsVersion) -osver $($Model.WindowsBuild) -category firmware
        Log -Message "Applying repository filter to $($Model.Model) repository to download: Firmware" -type 1 -LogFile $LogFile -Component HPIA
    }
    else {
        Log -Message "Not applying repository filter to download $($Model.Model) for: Firmware" -type 1 -LogFile $LogFile -Component HPIA
    }

    # Set HPIA Filter: Driverpack
    if ($HPIAFilter_Driverpack -eq "True") {
        Add-RepositoryFilter -platform $($Model.ProdCode) -os $($Model.WindowsVersion) -osver $($Model.WindowsBuild) -category driverpack
        Log -Message "Applying repository filter to $($Model.Model) repository to download: Driverpack" -type 1 -LogFile $LogFile -Component HPIA
    }
    else {
        Log -Message "Not applying repository filter to download $($Model.Model) for: DriverPack" -type 1 -LogFile $LogFile -Component HPIA
    }

    # Set HPIA Filter: BIOS
    if ($HPIAFilter_BIOS -eq "True") {
        Add-RepositoryFilter -platform $($Model.ProdCode) -os $($Model.WindowsVersion) -osver $($Model.WindowsBuild) -category bios
        Log -Message "Applying repository filter to $($Model.Model) repository to download: BIOS" -type 1 -LogFile $LogFile -Component HPIA
    }
    else {
        Log -Message "Not applying repository filter to download $($Model.Model) for: BIOS" -type 1 -LogFile $LogFile -Component HPIA
    }

    Log -Message "Invoking repository sync for $($Model.Model) $($Model.ProdCode). OS: $($Model.WindowsVersion), $($Model.WindowsBuild)" -LogFile $LogFile -Component HPIA
    Print -Message "Invoking repository sync for $($Model.Model) $($Model.ProdCode). OS: $($Model.WindowsVersion), $($Model.WindowsBuild) (might take some time)" -Indent 3 -Color Green
    
    try
    {
        Invoke-RepositorySync -Quiet

        Set-RepositoryConfiguration -Setting OfflineCacheMode -CacheValue Enable
        Start-Sleep -s 15
        Set-RepositoryConfiguration -Setting OfflineCacheMode -CacheValue Enable

        Log -Message "Repository sync for $($Model.Model) $($Model.ProdCode). OS: $($Model.WindowsVersion), $($Model.WindowsBuild) successful" -LogFile $LogFile -Component HPIA
        Print -Message "Repository sync for $($Model.Model) $($Model.ProdCode). OS: $($Model.WindowsVersion), $($Model.WindowsBuild) successful" -Indent 4 -Color Green
    }
    catch
    {
        Log -Message "Repository sync for $($Model.Model) $($Model.ProdCode). OS: $($Model.WindowsVersion), $($Model.WindowsBuild) NOT successful" -LogFile $LogFile -Component HPIA -Type 2
        Print -Message "Repository sync for $($Model.Model) $($Model.ProdCode). OS: $($Model.WindowsVersion), $($Model.WindowsBuild) NOT successful" -Indent 4 -Color Red
        Log -Message "Error code: $($_.Exception.Message)" -Type 3 -Component "Error" -LogFile $LogFile

    }

    Log -Message "Invoking repository cleanup for $($Model.Model) $($Model.ProdCode) repository for all selected categories" -LogFile $LogFile -Type 1 -Component HPIA
    Print -Message "Invoking repository cleanup for $($Model.Model) $($Model.ProdCode) repository for all selected categories" -Indent 3 -Color Green
    
    try
    {
        Invoke-RepositoryCleanup
    
        Set-RepositoryConfiguration -Setting OfflineCacheMode -CacheValue Enable
        Log -Message "Inventory cleanup for $($Model.Model) $($Model.ProdCode). OS: $($Model.WindowsVersion), $($Model.WindowsBuild) successful" -LogFile $LogFile -Component HPIA
        Print -Message "Inventory cleanup for $($Model.Model) $($Model.ProdCode). OS: $($Model.WindowsVersion), $($Model.WindowsBuild) successful" -Indent 4 -Color Green

    }
    catch
    {
        Log -Message "Inventory cleanup for $($Model.Model) $($Model.ProdCode). OS: $($Model.WindowsVersion), $($Model.WindowsBuild) NOT successful" -LogFile $LogFile -Component HPIA -Type 2
        Print -Message "Inventory cleanup for $($Model.Model) $($Model.ProdCode). OS: $($Model.WindowsVersion), $($Model.WindowsBuild) NOT successful" -Indent 4 -Color Red
        Log -Message "Error code: $($_.Exception.Message)" -Type 3 -Component "Error" -LogFile $LogFile

    }

    Log -Message "Confirm HPIA files are up to date for $($Model.Model) $($Model.ProdCode)" -LogFile $LogFile -Type 1 -Component HPIA
    Print -Message "Confirm HPIA files are up to date for $($Model.Model) $($Model.ProdCode)" -Indent 3 -Color Green

    $HPIARepoPath = Join-Path $ModelPath "HPImageAssistant.exe"
    $HPIAExist = Test-Path $HPIARepoPath -PathType Leaf -ErrorAction SilentlyContinue
    
    if (($HPIAVersionUpdated) -or (-not ($HPIAExist)))
    {
        Print -Message "Updating HPIA files in $ModelPath with robocopy" -Indent 4 -Color Green
        Log -Message "Updating HPIA files in $ModelPath with robocopy" -type 1 -LogFile $LogFile -Component HPIA

        $RobocopySource = "$($XMLInstallHPIA.Value)\HPIA Base"
        $RobocopyDest = $ModelPath
        $RobocopyArg = '"'+$RobocopySource+'"'+' "'+$RobocopyDest+'"'+' /e /b'
        $RobocopyCmd = "robocopy.exe"

        Start-Process -FilePath $RobocopyCmd -ArgumentList $RobocopyArg -Wait   
    } 
    else
    {
        Print -Message "No need to update HPIA, skipping" -Indent 4 -Color Green
        Log -Message "No need to update HPIA, skipping." -type 1 -LogFile $LogFile -Component HPIA
    }

    Print -Message "Check if offline cache folder exists" -Indent 3 -Color Green
    Log -Message "Check if offline cache folder exists" -type 1 -LogFile $LogFile -Component HPIA

    # Checking if offline folder is created.
    $OfflinePath = Join-Path $ModelRepositoryInitPath "cache\offline"

    if (-not (Test-Path $OfflinePath))
    {
        Print -Message "Offline cache folder does not exist, invoking sync" -Indent 4 -Color Green
        Log -Message "Offline cache folder does not exist, invoking sync" -type 1 -LogFile $LogFile -Component HPIA

        $OfflineFolderCreated = $false
        $OfflineCheckCount = 0
        Invoke-RepositorySync -Quiet
        Start-Sleep -Seconds 15
        Set-RepositoryConfiguration -Setting OfflineCacheMode -CacheValue Enable
        Start-Sleep -Seconds 10

        while (($OfflineFolderCreated -ne $true) -and $OfflineCheckCount -lt 10)
        {
            $OfflineCheckCount++
            
            if (Test-Path $OfflinePath)
            {
                $OfflineFolderCreated = $true
                Print -Message "Offline cache folder exists, will continue" -Indent 4 -Color Green
                Log -Message "Offline cache folder exists, will continue" -type 1 -LogFile $LogFile -Component HPIA

            }
            else
            {
                Print -Message "Offline cache folder doesn't exist, will try $(10-$OfflineCheckCount) more times" -Indent 5 -Color Yellow
                Log -Message "Offline cache folder doesn't exist, will try $(10-$OfflineCheckCount) more times" -type 1 -LogFile $LogFile -Component HPIA

            }
            
            Start-Sleep 5
        }

        if (-not ($OfflineFolderCreated))
        {
            Log -Message "Offlinefolder ($OfflinePath) still not detected, please run script manually again and update Distribution points" -type 3 -LogFile $LogFile -Component HPIA
            Print -Message "Offlinefolder ($OfflinePath) still not detected, please run script manually again and update Distribution points" -Indent 4 -Color Yellow
        }

    }

    #==========Stop Monitoring Changes===================

        Get-EventSubscriber | Unregister-Event

    #====================================================

    Print -Message "Starting ConfigMgr Tasks" -Color Green -Indent 3

    # ConfigMgr part start here    
    Import-Module $ConfigMgrModule

    # Customizations
    $initParams = @{}

    # Connect to the site's drive if it is not already present
    if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
        New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $SiteServer @initParams
        Log -Message "Mapping PSDrive for ConfigMgr" -type 1 -LogFile $LogFile -Component ConfigMgr

    }
    
    Set-location "$($SiteCode):\"

    if ((Test-path $CMfolderPath) -eq $false)
    {
        Log -Message "$CMFolderPath does not exists in ConfigMgr, creating folder path" -type 1 -LogFile $LogFile -Component ConfigMgr
        Print -Message "$CMFolderPath does not exists in ConfigMgr, creating folder path" -Color Green -Indent 4
        New-Item -ItemType directory -Path "$CMfolderPath"
        Log -Message "$CMFolderPath was successfully created in ConfigMgr" -type 1 -LogFile $LogFile -Component ConfigMgr

        if ((Test-path $CMfolderPath\$($Model.WindowsVersion)) -eq $false)
        {
            Log -Message "$CMfolderPath\$($Model.WindowsVersion) does not exists in ConfigMgr, creating folder path" -type 2 -LogFile $LogFile -Component ConfigMgr
            Print -Message "$CMfolderPath\$($Model.WindowsVersion) does not exists in ConfigMgr, creating folder path" -Color Green -Indent 4
            New-Item -ItemType directory -Path "$CMfolderPath\$($Model.WindowsVersion)" -Force
            Log -Message "$CMFolderPath was successfully created in ConfigMgr" -type 2 -LogFile $LogFile -Component ConfigMgr

            if ((Test-path $CMfolderPath\$($Model.WindowsVersion)\$WindowsBuild) -eq $false)
            {
                Log -Message "$CMfolderPath\$($Model.WindowsVersion)\$WindowsBuild does not exists in ConfigMgr, creating folder path" -type 2 -LogFile $LogFile -Component ConfigMgr
                Print -Message "$CMfolderPath\$($Model.WindowsVersion)\$WindowsBuild does not exists in ConfigMgr, creating folder path" -Color Green -Indent 4
                New-Item -ItemType directory -Path "$CMfolderPath\$($Model.WindowsVersion)\$WindowsBuild" -Force
                Log -Message "$CMFolderPath was successfully created in ConfigMgr" -type 2 -LogFile $LogFile -Component ConfigMgr
            }
        }
    }

    $SourcesLocation = $ModelPath # Set Source location
    $PackageName = "HPIA-$($Model.WindowsVersion)-$WindowsBuild-" + "$($Model.Model)" + " $($Model.ProdCode)" #Must be below 40 characters, hardcoded variable, will be used inside the ApplyHPIA.ps1 script, Please dont change this.
    $PackageDescription = "$($Model.WindowsVersion) $WindowsBuild-" + "$($Model.Model)" + " $($Model.ProdCode)"
    $PackageManufacturer = "HP" # hardcoded variable, will be used inside the ApplyHPIA.ps1 script, Please dont change this.
    $PackageVersion = "$WindowsBuild"
    $SilentInstallCommand = ""
    
    Print -Message "Checking if $PackageName exists in ConfigMgr" -Color Green -Indent 4
    Log -Message "Checking if $PackageName exists in ConfigMgr" -type 1 -LogFile $LogFile -Component ConfigMgr
    # Check if package exists in ConfigMgr, if not it will be created.
    $PackageExist = Get-CMPackage -Fast -Name $PackageName
    If ([string]::IsNullOrWhiteSpace($PackageExist)){
        Log -Message "$PackageName does not exists in ConfigMgr" -type 1 -LogFile $LogFile -Component ConfigMgr
        Log -Message "Creating $PackageName in ConfigMgr" -type 1 -LogFile $LogFile -Component ConfigMgr
        Print -Message "$PackageName does not exists in ConfigMgr, creating it." -Color Green -Indent 5

        try
        {
            New-CMPackage -Name $PackageName -Description $PackageDescription -Manufacturer $PackageManufacturer -Version $PackageVersion -Path $SourcesLocation | Out-Null
            Set-CMPackage -Name $PackageName -DistributionPriority Normal -CopyToPackageShareOnDistributionPoints $True -EnableBinaryDeltaReplication $True | Out-Null
            Log -Message "$PackageName is created in ConfigMgr" -LogFile $LogFile -Type 1 -Component ConfigMgr    
            Start-CMContentDistribution -PackageName "$PackageName" -DistributionPointGroupName "$DPGroupName" | Out-Null
            Log -Message "Starting to send out $PackageName to $DPGroupName" -type 1 -LogFile $LogFile -Component ConfigMgr
        
            $MovePackage = Get-CMPackage -Fast -Name $PackageName        
            Move-CMObject -FolderPath "$CMfolderPath\$($Model.WindowsVersion)\$WindowsBuild" -InputObject $MovePackage | Out-Null
            Log -Message "Moving ConfigMgr package to $CMfolderPath\$($Model.WindowsVersion)\$WindowsBuild" -LogFile $LogFile -Component ConfigMgr -Type 1
        
            Set-Location -Path "$($InstallPath)"
            Print -Message "$PackageName is created in ConfigMgr and distributed to $DPGroupName" -Color Green -Indent 6
            Log -Message "$PackageName is created in ConfigMgr and distributed to $DPGroupName" -LogFile $LogFile -Component ConfigMgr -Type 1

        }
        catch
        {
            Print -Message "Failed to create package $PackageName and/or distribute to DPGroup $DPGroupName" -Color Red -Indent 6
            Log -Message "Failed to create package $PackageName and/or distribute to DPGroup $DPGroupName" -LogFile $LogFile -Component ConfigMgr -Type 1
            Log -Message "Error code: $($_.Exception.Message)" -type 3 -Component "Script" -LogFile $LogFile

        }
    }
    else 
    {
        If ($GLOBAL:UpdatePackage -eq $True){
            Print -Message "$PackageName exists in ConfigMgr and changes was made to the repository, updating content" -Color Green -Indent 5
            Log -Message "$PackageName exists in ConfigMgr and changes was made to the repository, updating content" -type 2 -Component ConfigMgr -LogFile $LogFile
            try
            {
                Update-CMDistributionPoint -PackageName "$PackageName"

            }
            catch 
            {
                Log -Message "Something went wrong when trying to update content on DPs" -Type 3 -Component "Error" -LogFile $LogFile
                Log -Message "Error code: $($_.Exception.Message)" -Type 3 -Component "Error" -LogFile $LogFile

            }
        }
        else
        {
            Print -Message "$PackageName exists in ConfigMgr but no changes was made to the repository during sync, nothing to do." -Color Green -Indent 5
            Log -Message "$PackageName exists in ConfigMgr but no changes was made to the repository during sync, nothing to do." -type 1 -LogFile $LogFile -Component ConfigMgr

        }
        Set-Location -Path $($InstallPath)
        Log -Message "$($Model.Model) is done, continue with next model in the list." -type 1 -LogFile $LogFile
        Print -Message "$($Model.Model) is done, continue with next model (if any) in the list" -Color Green -Indent 2
    }    
}

Set-Location -Path "$($InstallPath)"
$stopwatch.Stop()
$FinalTime = $stopwatch.Elapsed

Print -Message "Repository update complete. Runtime: $FinalTime" -Color Cyan
Log -Message "Runtime: $FinalTime" -LogFile $Logfile -Type 1 -Component HPIA
Log -Message "Repository Update Complete" -LogFile $LogFile -Type 1 -Component HPIA
Log -Message "----------------------------------------------------------------------------" -LogFile $LogFile