<# Author: Daniel Gråhns, Nicklas Eriksson
 Date: 2021-02-11
 Purpose: Download HP Drivers to repository and use with Webservice and TaskSequence

 Version: 1.0
 Changelog: 1.0 - 2021-02-11 - Nicklas Eriksson -  Script Edited and fixed Daniels crappy hack and slash code :)
            1.1 - 2021-02-18 - Nicklas Eriksson - Added HPIA to download to HPIA Download instead to Root Directory, Added BIOSPwd should be copy to HPIA so BIOS upgrades can be run during OSD. 
            1.2 - 2021-04-13 - Nicklas Eriksson - Bug fixed when if offline folder does not exists. Thanks to Andreas Molin who found this and corrected it.  
            TO-Do
 - Can we create an if around this Monitor changes if the path exists go into there if not skip since it throws an error?
 Credit, inspiration and copy/paste code from: garytown.com, dotnet-helpers.com, ConfigMgr.com, www.imab.dk, Ryan Engstrom
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage='Path to XML Configuration File')]
    [string]$Config
)


$ScriptVersion = "1.2"


#$Config = "E:\Scripts\ImportHPIA\Config.xml" #(.\ImportHPIA.ps1 -config .\config.xml)

if (Test-Path -Path $Config) {
        try { 
            $Xml = [xml](Get-Content -Path $Config -Encoding UTF8)
            #Log -Message "Successfully loaded $Config" -LogFile $Logfile
        }
        catch {
            $ErrorMessage = $_.Exception.Message
            #Log -Message "Error, could not read $Config" -Level Error -LogFile $Logfile
            #Log -Message "Error message: $ErrorMessage" -Level Error -LogFile $Logfile
            Exit 1
        }

 }
 

# Getting information from Config File
$InstallPath = $Xml.Configuration.Install | Where-Object {$_.Name -like 'InstallPath'} | Select-Object -ExpandProperty "Value"
$XMLInstallHPIA = $Xml.Configuration.Install | Where-Object {$_.Name -like 'InstallHPIA'} | Select-Object 'Enabled','Value'
$SiteCode = $Xml.Configuration.Install | Where-Object {$_.Name -like 'SiteCode'} | Select-Object -ExpandProperty 'Value'
$CMFolderPath = $Xml.Configuration.Install | Where-Object {$_.Name -like 'CMFolderPath'} | Select-Object -ExpandProperty 'Value'
$ConfigMgrModule = $Xml.Configuration.Install | Where-Object {$_.Name -like 'ConfigMgrModule'} | Select-Object -ExpandProperty 'Value'
$InstallHPCML = $Xml.Configuration.Install | Where-Object {$_.Name -like 'InstallHPCML'} | Select-Object -ExpandProperty 'Enabled'
$RepositoryPath = $Xml.Configuration.Install | Where-Object {$_.Name -like 'RepositoryPath'} | Select-Object -ExpandProperty 'Value'
$SupportedModelsCSV = $Xml.Configuration.Install | Where-Object {$_.Name -like 'SupportComputerModels'} | Select-Object -ExpandProperty 'Value'
$XMLSSMONLY = $Xml.Configuration.Feature | Where-Object {$_.Name -like 'SSMOnly'} | Select-Object -ExpandProperty 'Enabled'
$XMLCategory1 = $Xml.Configuration.Feature | Where-Object {$_.Name -like 'Category1'} | Select-Object -ExpandProperty 'Enabled'
$XMLCategory2 = $Xml.Configuration.Feature | Where-Object {$_.Name -like 'Category2'} | Select-Object -ExpandProperty 'Enabled'
$XMLCategory3 = $Xml.Configuration.Feature | Where-Object {$_.Name -like 'Category3'} | Select-Object -ExpandProperty 'Enabled'
$XMLCategory4 = $Xml.Configuration.Feature | Where-Object {$_.Name -like 'Category4'} | Select-Object -ExpandProperty 'Enabled'
$DPGroupName = $Xml.Configuration.Feature | Where-Object {$_.Name -like 'DPGroupName'} | Select-Object -ExpandProperty 'Value'
$XMLEnableSMTP = $Xml.Configuration.Option | Where-Object {$_.Name -like 'EnableSMTP'} | Select-Object 'Enabled','SMTP',"Adress"
#$XMLLogfile = $Xml.Configuration.Option | Where-Object {$_.Name -like 'Logfile'} | Select-Object -ExpandProperty 'Value'


# Hardcoded variabels in the script.
$LogFile = "$InstallPath\RepositoryUpdate.log" #Filename for the logfile.
$OS = "Win10" #OS do not change this.


function Get-Log {
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


Get-Log  -Message  "<--------------------------------------------------------------------------------------------------------------------->"  -type 2 -LogFile $LogFile
Write-host "Info: Successfully loaded ConfigFile from $Config"
Get-Log -Message "Successfully loaded ConfigFile from $Config" -LogFile $Logfile
Get-LOg -Message "Script was started with version: $($ScriptVersion)" -type 1 -LogFile $LogFile 

# CHeck if HPCML should autoupdate from Powershell gallery if's specified in the config.
if ($InstallHPCML -eq "True")
{
        Get-Log -Message "HPCML was enbabled to autoinstall in ConfigFile, starting to install HPCML" -type 1 -LogFile $LogFile
        Write-host "Info: HPCML was enbabled to autoinstall in ConfigFile, starting to install HPCML"
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 # Force Powershell to use TLS1.2
        # make sure Package NuGet is up to date 
        Install-Module -Name PowerShellGet -Force # install the latest version of PowerSHellGet module
        Install-Module -Name HPCMSL -Force -AcceptLicense
        Get-Log -Message "HPCML was successfully updated" -type 1 -LogFile $LogFile
        Write-host "Info: HPCML was successfully updated" -ForegroundColor Green

}
else
{
    Get-Log -Message "HPCML was not enbabled to autoinstall from Powershell Gallery in ConfigFile" -type 1 -LogFile $LogFile

}

# Check if HPIA Installer was updated and create download folder for HPIA.
if ((Test-path -Path "$($XMLInstallHPIA.Value)\HPIA Download") -eq $false)
{
    Get-Log -Message "HPIA Download folder does not exists, creating HPIA Download folder" -type 1 -LogFile $LogFile
    Write-host "Info: HPIA Download folder does not exists"
    Write-host "Info: Creating HPIA Download folder" -ForegroundColor Green
    New-Item -ItemType Directory -Path "$($XMLInstallHPIA.Value)\HPIA Download"
    New-Item -ItemType File -Path "$($XMLInstallHPIA.Value)\HPIA Download\Dont Delete the latest SP-file.txt"
}
else
{
    Get-Log -Message "HPIA Download folder exists, no need to create folder" -type 1 -LogFile $LogFile
    Write-host "Info: HPIA Download folder exists, no need to create folder"
}

$CurrentHPIAVersion = Get-ChildItem "$($XMLInstallHPIA.Value)\HPIA Download" -Name SP*.*

# CHeck if HPIA should autoupdate from HP if's specified in the config.

if ($XMLInstallHPIA.Enabled -eq "True")
{
        Get-Log -Message "HPIA was  enbabled to autoinstall in ConfigFile, starting to autoupdate HPIA" -type 1 -LogFile $LogFile
        Write-host "Info: HPIA was  enbabled to autoinstall in ConfigFile, starting to autoupdate HPIA"
        Set-location -Path "$($XMLInstallHPIA.Value)\HPIA Download"
        Install-HPImageAssistant -Extract -DestinationPath "$($XMLInstallHPIA.Value)\HPIA Base"
        Set-Location -path $InstallPath
        Get-Log -Message "HPIA was  successfully updated in $($XMLInstallHPIA.Value)\HPIA Base" -type 1 -LogFile $LogFile
        Write-host "Info: HPIA was  successfully updated in $($XMLInstallHPIA.Value)\HPIA Base" -ForegroundColor Green
        
}
else
{
    Get-Log -Message "HPIA was not enabled to autoinstall in ConfigFile" -type 1 -LogFile $LogFile
    
}

# Copy BIOS PWD to HPIA. 
$BIOS = Get-ChildItem -Path "$($XMLInstallHPIA.Value)\*.bin" # Check for any Password.BIN file. 
if ((Test-path -Path "$($XMLInstallHPIA.Value)\HPIA Base\$($BIOS.Name)") -eq $false) {
    Write-Host "Info: BIOS File does not exists, need to copy file to HPIA."
    Get-Log -Message "BIOS File does not exists, need to copy file to HPIA." -type 1 -LogFile $LogFile
    Copy-Item -Path $BIOS -Destination "$($XMLInstallHPIA.Value)\HPIA Base"
} else {
    Write-host "Info: BIOS File exists in HPIA or does not exits in root, no need to copy" -ForegroundColor Green
    Get-Log -Message "BIOS File exists in HPIA or does not exits in root, no need to copy" -type 1 -LogFile $LogFile
}

# If HPIA Installer was not updated, set false flag value
$NewHPIAVersion = Get-ChildItem "$($XMLInstallHPIA.Value)\HPIA Download" -Name SP*.* -ErrorAction SilentlyContinue | Select-Object -last 1

if($CurrentHPIAVersion -eq $NewHPIAVersion) {
    $HPIAVersionUpdated = "False"
    Write-host "Info: HPIA was not updated, skipping to set HPIA to copy to driverpackages." -ForegroundColor Green
    Get-Log -Message "HPIA was not updated, skipping to set HPIA to copy to driverpackages." -type 1 -LogFile $LogFile
    } else {
    $HPIAVersionUpdated = "True"
    Write-host "Info: HPIA was updated, will update in each driverpackage" -ForegroundColor Green
    Get-Log -Message "HPIA was updated will update HPIA in each Driverpackage" -type 1 -LogFile $LogFile
    }

# Check if SSM is enabled in the config.
if ($XMLSSMONLY -eq "True") {
    $SSMONLY = "ssm"
} else {
        Get-Log -Message "SSM not enabled in ConfigFile" -type 1 -LogFile $LogFile
}

# Check if Category1 is enabled in the config.
if ($XMLCategory1 -eq "True") {
    $Category1 = "dock"
    Get-Log -Message "Added dock drivers for download" -type 1 -LogFile $LogFile
}
else{
        Get-Log -Message "Not enabled to download dock in ConfigFile" -type 2 -LogFile $LogFile
}

# Check if Category2 is enabled in the config.
if ($XMLCategory2 -eq "True") {
    $Category2 = "driver"
    Get-Log -Message "Added drivers for download" -type 1 -LogFile $LogFile
}
else {
        Get-Log -Message "Not Enabled to download drivers in ConfigFile" -type 2 -LogFile $LogFile
}

# Check if Category3 is enabled in the config.
if ($XMLCategory3 -eq "True") {
    $Category3 = "firmware"
    Get-Log -Message "Added firmware for download" -type 1 -LogFile $LogFile
}
else {
        Get-Log -Message "Not Enabled to download firmware in ConfigFile" -type 1 -LogFile $LogFile
}

# Check if Category4 is enabled in the config.
if ($XMLCategory4 -eq "True") {
    $Category4 = "driverpack"
    Get-Log -Message "Added driverpacks for download" -type 1 -LogFile $LogFile

}
else {
        Get-Log -Message "Not Enabled to download Driverpack in ConfigFile" -type 1 -LogFile $LogFile
}
# Check if Email notificaiton is enabled in the config.
if ($XMLEnableSMTP.Enabled -eq "True") {
    $SMTP = $($XMLEnableSMTP.SMTP)
    $EMAIL = $($XMLEnableSMTP.Adress)
    Get-Log -Message "Added SMTP: $SMTP and EMAIL: $EMAIL" -type 1 -LogFile $LogFile
} 
else {
        Get-Log -Message "Email notification is not enabled in the Config" -type 1 -LogFile $LogFile
}

#Importing supported computer models CSV file
if ($SupportedModelsCSV -match ".csv") {
				$ModelsToImport = Import-Csv -Path $SupportedModelsCSV
				Get-Log -Message "Info: $($ModelsToImport.Model.Count) models found" -Type 1 -LogFile $LogFile
                Write-host "Info: $($ModelsToImport.Model.Count) models found"
}

$HPModelsTable = foreach ($Model in $ModelsToImport) {
    @(
    @{ ProdCode = "$($Model.ProductCode)"; Model = "$($Model.Model)"; OSVER = $Model.WindowsVersion }
    )
    Get-Log -Message "Added $($Model.ProductCode) $($Model.Model) $($Model.WindowsVersion) to download list" -type 1 -LogFile $LogFile
    Write-host "Info: Added $($Model.ProductCode) $($Model.Model) $($Model.WindowsVersion) to download list" 
}

foreach ($Model in $HPModelsTable) {
    
    # Set OSVersion for 2009 to 20H2.  
    if($Model.OSVER -eq "2009") # Want to set OSVersion to 20H2 in ConfigMgr, and must use 2009 to download Drivers from HP.
    {
         $OSVER = "20H2"
         
    }
    else
    {
        $OSVER = $Model.OSVER
    }

    $GLOBAL:UpdatePackage = $False
#==============Monitor Changes for Update Package======================================================

   $filewatcher = New-Object System.IO.FileSystemWatcher
    
    #Mention the folder to monitor
    $filewatcher.Path = "$($RepositoryPath)\$OSVER\$($Model.Model) $($Model.ProdCode)\"
    $filewatcher.Filter = "*.cva"
    #include subdirectories $true/$false
    $filewatcher.IncludeSubdirectories = $False
    $filewatcher.EnableRaisingEvents = $true  
### DEFINE ACTIONS AFTER AN EVENT IS DETECTED
    $writeaction = { $path = $Event.SourceEventArgs.FullPath
                $changeType = $Event.SourceEventArgs.ChangeType
                $logline = "$(Get-Date), $changeType, $path"
                Write-Host $logline #Add-content
                Write-Host "Info: Setting Update Package to True"
                $GLOBAL:UpdatePackage = $True
                #Write-Host "Info: Write Action $UpdatePackage"
              }
              
### DECIDE WHICH EVENTS SHOULD BE WATCHED
    Register-ObjectEvent $filewatcher "Created" -Action $writeaction
    Register-ObjectEvent $filewatcher "Changed" -Action $writeaction
    Register-ObjectEvent $filewatcher "Deleted" -Action $writeaction
    Register-ObjectEvent $filewatcher "Renamed" -Action $writeaction
#=====================================================================================================================


    Log -Message "----------------------------------------------------------------------------" -LogFile $LogFile
    Log -Message "Checking if repository for model $($Model.Model) aka $($Model.ProdCode) exists" -LogFile $LogFile
    write-host "Info: Checking if repository for model $($Model.Model) aka $($Model.ProdCode) exists"
    if (Test-Path "$($RepositoryPath)\$OSVER\$($Model.Model) $($Model.ProdCode)\Repository") { Log -Message "Repository for model $($Model.Model) aka $($Model.ProdCode) already exists" -LogFile $LogFile }
    if (-not (Test-Path "$($RepositoryPath)\$OSVER\$($Model.Model) $($Model.ProdCode)\Repository")) {
        Log -Message "Repository for $($Model.Model) $($Model.ProdCode) does not exist, creating now" -LogFile $LogFile
        Write-host "Info: Repository for $($Model.Model) $($Model.ProdCode) does not exist, creating now"
        New-Item -ItemType Directory -Path "$($RepositoryPath)\$OSVER\$($Model.Model) $($Model.ProdCode)\Repository"
        if (Test-Path "$($RepositoryPath)\$OSVER\$($Model.Model) $($Model.ProdCode)\Repository") {
            Log -Message "$($Model.Model) $($Model.ProdCode) HPIA folder and repository subfolder successfully created" -LogFile $LogFile
            Write-host "Info: $($Model.Model) $($Model.ProdCode) HPIA folder and repository subfolder successfully created" -ForegroundColor Green
            }
        else {
            Log -Message "Failed to create repository subfolder!" -LogFile $LogFile -Type 3
            Write-host "Info: Failed to create repository subfolder!" -ForegroundColor Red
            Exit
        }
    }
    if (-not (Test-Path "$($RepositoryPath)\$OSVER\$($Model.Model) $($Model.ProdCode)\Repository\.repository")) {
        Log -Message "Repository not initialized, initializing now" -LogFile $LogFile
        Write-host "Info: Repository not initialized, initializing now"
        Set-Location -Path "$($RepositoryPath)\$OSVER\$($Model.Model) $($Model.ProdCode)\Repository"
        Initialize-Repository
        if (Test-Path "$($RepositoryPath)\$OSVER\$($Model.Model) $($Model.ProdCode)\Repository\.repository") {
            Write-host "Info: $($Model.Model) $($Model.ProdCode) repository successfully initialized"
            Log -Message "$($Model.Model) $($Model.ProdCode) repository successfully initialized" -LogFile $LogFile
        }
        else {
            Log -Message "Failed to initialize repository for $($Model.Model) $($Model.ProdCode)" -LogFile $LogFile -Type 3
            Write-host "Info: Failed to initialize repository for $($Model.Model) $($Model.ProdCode)" -ForegroundColor Red
            Exit
        }
    }    
    
    Log -Message "Set location to $($Model.Model) $($Model.ProdCode) repository" -LogFile $LogFile
    Set-Location -Path "$($RepositoryPath)\$OSVER\$($Model.Model) $($Model.ProdCode)\Repository"
    
    if ($XMLEnableSMTP.Enabled -eq "True") {
        Set-RepositoryNotificationConfiguration $SMTP
        Add-RepositorySyncFailureRecipient -to $EMAIL
        Log -Message "Configured notification for $($Model.Model) $($Model.ProdCode) with SMTP: $SMTP and Email: $EMAIL" -LogFile $LogFile
    }  
    
    Log -Message "Remove any existing repository filter for $($Model.Model) repository" -LogFile $LogFile
    Remove-RepositoryFilter -platform $($Model.ProdCode) -yes
    
    Log -Message "Applying repository filter for $($Model.Model) repository" -LogFile $LogFile
    if ($XMLCategory1 -eq "True") {
           Add-RepositoryFilter -platform $($Model.ProdCode) -os $OS -osver $($Model.OSVER) -category $Category1
           Log -Message "Applying repository filter to $($Model.Model) repository to download: $Category1" -type 1 -LogFile $LogFile

    }
    else {
        Log -Message "Not applying repository filter to download $($Model.Model) for: dock" -type 1 -LogFile $LogFile

    }
    if ($XMLCategory2 -eq "True") {
        Add-RepositoryFilter -platform $($Model.ProdCode) -os $OS -osver $($Model.OSVER) -category $Category2
        Log -Message "Applying repository filter to $($Model.Model) repository to download: $Category2" -type 1 -LogFile $LogFile

    }
    else {
        Log -Message "Not applying repository filter to download $($Model.Model) for: Driver" -type 1 -LogFile $LogFile

    }
    if ($XMLCategory3 -eq "True") {
        Add-RepositoryFilter -platform $($Model.ProdCode) -os $OS -osver $($Model.OSVER) -category $Category3
        Log -Message "Applying repository filter to $($Model.Model) repository to download: $Category3" -type 1 -LogFile $LogFile
    }
    else {
        Log -Message "Not applying repository filter to download $($Model.Model) for: Firmware" -type 2 -LogFile $LogFile
    }
    if ($XMLCategory4 -eq "True") {
        Add-RepositoryFilter -platform $($Model.ProdCode) -os $OS -osver $($Model.OSVER) -category $Category4
        Log -Message "Applying repository filter to $($Model.Model) repository to download: $Category4" -type 2 -LogFile $LogFile

    }
    else {
        Log -Message "Not applying repository filter to download $($Model.Model) for: DriverPack" -type 1 -LogFile $LogFile
    }

    Log -Message "Invoking repository sync for $($Model.Model) $($Model.ProdCode) repository $os, $($Model.OSVER), $Category1 and $Category2 and $Category3 and $Category4" -LogFile $LogFile
    Write-host "Info: Invoking repository sync for $($Model.Model) $($Model.ProdCode) repository $os, $($Model.OSVER), $Category1 and $Category2 and $Category3 and $Category4"
    Invoke-RepositorySync
    Set-RepositoryConfiguration -Setting OfflineCacheMode -CacheValue Enable
    Start-Sleep -s 15
    Set-RepositoryConfiguration -Setting OfflineCacheMode -CacheValue Enable

    Log -Message "Invoking repository cleanup for $($Model.Model) $($Model.ProdCode) repository for $Category1 and $Category2 and $Category3 and $Category4 categories" -LogFile $LogFile
    Write-host "Info: Invoking repository cleanup for $($Model.Model) $($Model.ProdCode) repository for $Category1 and $Category2 and $Category3 and $Category4 categories"
    Invoke-RepositoryCleanup
    Set-RepositoryConfiguration -Setting OfflineCacheMode -CacheValue Enable
    Log -Message "Confirm HPIA files are up to date for $($Model.Model) $($Model.ProdCode)" -LogFile $LogFile 
    Write-host "Info: Confirm HPIA files are up to date for $($Model.Model) $($Model.ProdCode)" 


    if ($HPIAVersionUpdated -eq "True") {
        Write-Host "Info: Running HPIA Update"
        Log -Message "Running HPIA Update" -type 1 -LogFile $LogFile
        $RobocopySource = "$($XMLInstallHPIA.Value)\HPIA Base"
        $RobocopyDest = "$($RepositoryPath)\$OSVER\$($Model.Model) $($Model.ProdCode)"
        $RobocopyArg = '"'+$RobocopySource+'"'+' "'+$RobocopyDest+'"'+' /xc /xn /xo /fft /e /b /copyall'
        $RobocopyCmd = "robocopy.exe"
        Start-Process -FilePath $RobocopyCmd -ArgumentList $RobocopyArg -Wait
        
        Write-Host "Checking if offline folder is created"
        $OfflinePath = "$($RepositoryPath)\$OSVER\$($Model.Model) $($Model.ProdCode)\Repository\.repository\cache\offline"
        if(!(Test-Path $OfflinePath)){
            Write-Host "Folder not detected, running RepositoryConfiguration again in 20 seconds"
            Log -Message "Folder not detected, running RepositoryConfiguration again in 20 seconds" -type 1 -LogFile $LogFile
            Start-Sleep -Seconds 20
            Invoke-RepositorySync
            Start-Sleep -Seconds 15
            Set-RepositoryConfiguration -Setting OfflineCacheMode -CacheValue Enable
            Start-Sleep -Seconds 10
            if(!(Test-Path $OfflinePath)){
                Write-Host "Offlinefolder still not detected, please run script manually again and update Distribution points"
                Log -Message "Offlinefolder still not detected, please run script manually again and update Distribution points" -type 1 -LogFile $LogFile

            }

        } else {

            Write-Host "Info: No need to update HPIA, skipping this step."
            Log -Message "No need to update HPIA, skipping." -type 1 -LogFile $LogFile

        }
    }

#==========Stop Monitoring Changes===================

    Get-EventSubscriber | Unregister-Event

#====================================================

    
    Import-Module $ConfigMgrModule
    Set-location "$($SiteCode):\"

    $SourcesLocation = $RobocopyDest
    $PackageName = "HPIA-$OSVER-" + "$($Model.Model)-" + "$($Model.ProdCode)" #Must be below 40 characters
    $PackageDescription = "$OSVER-" + "$($Model.Model)-" + "$($Model.ProdCode)"
    $PackageManufacturer = "HP"
    $PackageVersion = "$OSVER"
    $SilentInstallCommand = ""
    
    $PackageExist = Get-CMPackage -Fast -Name $PackageName
    If ([string]::IsNullOrWhiteSpace($PackageExist)){
        #Write-Host "Does not Exist"
        Log -Message "$PackageName does not exists in ConfigMgr" -type 2 -LogFile $LogFile
        Log -Message "Creating $PackageName in ConfigMgr" -type 2 -LogFile $LogFile
        Write-host "Info: $PackageName does not exists in ConfigMgr"
        Write-host "Info: Creating $PackageName in ConfigMgr"
        New-CMPackage -Name $PackageName -Description $PackageDescription -Manufacturer $PackageManufacturer -Version $PackageVersion -Path $SourcesLocation
        Set-CMPackage -Name $PackageName -DistributionPriority Normal -CopyToPackageShareOnDistributionPoints $True -EnableBinaryDeltaReplication $True
        Start-CMContentDistribution -PackageName  "$PackageName" -DistributionPointGroupName "$DPGroupName"

        $MovePackage = Get-CMPackage -Fast -Name $PackageName
        Move-CMObject -FolderPath $CMFolderPath -InputObject $MovePackage

        Set-Location -Path "$($InstallPath)"
        Write-host "Info: $PackageName is created in ConfigMgr"
        Log -Message "$PackageName is created in ConfigMgr" -LogFile $LogFile
    }
    Else {
        #Write-Host "Package Already Exist"
        #Write-Host "Updatepackage: $GLOBAL:UpdatePackage"
        If ($GLOBAL:UpdatePackage -eq $True){
            Write-Host "Info: Changes was made updating ConfigMgrPkg: $PackageName" -ForegroundColor Green
            Log -Message "Changes made Updating ConfigMgrPkg: $PackageName on DistributionPoint" -type 2 -LogFile $LogFile
            Update-CMDistributionPoint -PackageName "$PackageName"
        }
        Else {
            Write-Host "Info: No Changes was Made, not updating ConfigMgrPkg: $PackageName on DistributionPoint" -ForegroundColor Green
            Log -Message "No Changes was Made, not updating ConfigMgrPkg: $PackageName on DistributionPoint" -type 2 -LogFile $LogFile

        }
            Set-Location -Path $($InstallPath)
            Write-host "Info: $($Model.Model) is done, contiune with next model in the list."  -ForegroundColor Green
            Log -Message "$($Model.Model) is done, contiune with next model in the list." -type 1 -LogFile $LogFile
    }
    
}
Set-Location -Path "$($InstallPath)"
Write-host "Info: Repository Update Complete" -ForegroundColor Green
Log -Message "Repository Update Complete" -LogFile $LogFile
Log -Message "----------------------------------------------------------------------------" -LogFile $LogFile