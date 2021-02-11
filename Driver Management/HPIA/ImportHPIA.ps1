# Author: Daniel Gråhns, Nicklas Eriksson
# Date: 2021-02-11
# Purpose: Download HP Drivers to repository and use with ConfigMgr Webservice from MSEndpointMgr.com and TaskSequence
#
# Version: 1.0
# Changelog: 1.0 - 2021-02-11 - Nicklas Eriksson -  Script Edited and fixed Daniels crappy hack and slash code :)
#         
# Credit, inspiration and copy/paste code from: garytown.com, dotnet-helpers.com, ConfigMgr.com, www.imab.dk


[CmdletBinding()]
param(
    [Parameter(HelpMessage='Path to XML Configuration File')]
    [string]$Config
)


$ScriptVersion = "1.0"


#$Config = "E:\Scripts\ImportHPIA\Config.xml" (.\ImportHPIA.ps1 -config .\config.xml)

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
$LogFile = "$InstallPath\RepoUpdate.log" #Filename for the logfile.
$OS = "Win10" #OS do not change this.


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


Log -LogFile $LogFile "<--------------------------------------------------------------------------------------------------------------------->"  -type 2
Log -Message "Successfully loaded $Config" -LogFile $Logfile
LOg -LogFile $LogFile "Powershellscript was started with scriptversion: $($ScriptVersion)" -type 1

# CHeck if HPCML should autoupdate from Powershell gallery if's specified in the config.
if ($InstallHPCML -eq "True")
{
        Log -Message "HPCML was  enbabled to autoinstall in ConfigFile, starting to install HPCML" -type 1 -LogFile $LogFile
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        # make sure Package NuGet is up to date 
        Install-Module -Name PowerShellGet -Force # install the latest version of PowerSHellGet module
        Install-Module -Name HPCMSL -Force -AcceptLicense
        Log -Message "HPCML was  successfully updated" -type 1 -LogFile $LogFile

}
else
{
    Log -Message "HPCML was not enbabled to autoinstall from Powershell Gallery in ConfigFile" -type 1 -LogFile $LogFile

}

# CHeck if HPIA should autoupdate from HP if's specified in the config.

if ($XMLInstallHPIA.Enabled -eq "True")
{
        Log -Message "HPIA was  enbabled to autoinstall in ConfigFile, starting to autoupdate HPIA" -type 1 -LogFile $LogFile
        Install-HPImageAssistant -Extract -DestinationPath "$($XMLInstallHPIA.Value)\HPIA Base"
        Log -Message "HPIA was  successfully updated in $($XMLInstallHPIA.Value)\HPIA Base" -type 1 -LogFile $LogFile
        
}
else
{
    Log -Message "HPIA was not enbabled to autoinstall in ConfigFile" -type 1 -LogFile $LogFile

}

# Check if SSM is enabled in the config.
if ($XMLSSMONLY -eq "True")
{
    $SSMONLY = "ssm"
}
else
{
        Log -Message "SSM not enabled in ConfigFile" -type 1 -LogFile $LogFile

}

# Check if Category1 is enabled in the config.
if ($XMLCategory1 -eq "True")
{
    $Category1 = "dock"
    Log -Message "Added dock drivers for download" -type 1 -LogFile $LogFile

}
else
{
        Log -Message "Not enabled to download dock in ConfigFile" -type 2 -LogFile $LogFile

}

# Check if Category2 is enabled in the config.
if ($XMLCategory2 -eq "True")
{
    $Category2 = "driver"
    Log -Message "Added drivers for download" -type 1 -LogFile $LogFile

}
else
{
        Log -Message "Not Enabled to download drivers in ConfigFile" -type 2 -LogFile $LogFile

}

# Check if Category3 is enabled in the config.
if ($XMLCategory3 -eq "True")
{
    $Category3 = "firmware"
    Log -Message "Added firmware for download" -type 1 -LogFile $LogFile

}
else
{
        Log -Message "Not Enabled to download firmware in ConfigFile" -type 1 -LogFile $LogFile

}

# Check if Category4 is enabled in the config.
if ($XMLCategory4 -eq "True")
{
    $Category4 = "driverpack"
    Log -Message "Added driverpacks for download" -type 1 -LogFile $LogFile

}
else
{
        Log -Message "Not Enabled to download Driverpack in ConfigFile" -type 1 -LogFile $LogFile

}
# Check if Email notificaiton is enabled in the config.
if ($XMLEnableSMTP.Enabled -eq "True")
{
    $SMTP = $($XMLEnableSMTP.SMTP)
    $EMAIL = $($XMLEnableSMTP.Adress)
    Log -Message "Added SMTP: $SMTP and EMAIL: $EMAIL" -type 1 -LogFile $LogFile

}
else
{
        Log -Message "Email notification is not enabled in the Config" -type 1 -LogFile $LogFile

}

#Importing CSV file
if ($SupportedModelsCSV -match ".csv") 
{
				$ModelsToImport = Import-Csv -Path $SupportedModelsCSV
				Log -Message "Info: $($ModelsToImport.Model.Count) models found" -Type 1 -LogFile $LogFile
}

$HPModelsTable = foreach ($Model in $ModelsToImport)
{
    @(
    @{ ProdCode = "$($Model.ProductCode)"; Model = "$($Model.Model)"; OSVER = $Model.WindowsVersion }
    )
    Log -Message "Added $($Model.ProductCode) $($Model.Model) $($Model.WindowsVersion) to download list" -type 1 -LogFile $LogFile

}

foreach ($Model in $HPModelsTable) {
    
    # Set OSVersion for 2009 to 20H2.  
    if($Model.OSVER -eq "2009")
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
    $filewatcher.Filter = "*.*"
    #include subdirectories $true/$false
    $filewatcher.IncludeSubdirectories = $False
    $filewatcher.EnableRaisingEvents = $true  
### DEFINE ACTIONS AFTER AN EVENT IS DETECTED
    $writeaction = { $path = $Event.SourceEventArgs.FullPath
                $changeType = $Event.SourceEventArgs.ChangeType
                $logline = "$(Get-Date), $changeType, $path"
                Write-Host $logline #Add-content
                Write-Host "Setting Update Package to True"
                $GLOBAL:UpdatePackage = $True
                Write-Host "Write Action $UpdatePackage"
              }
              
### DECIDE WHICH EVENTS SHOULD BE WATCHED
    Register-ObjectEvent $filewatcher "Created" -Action $writeaction
    Register-ObjectEvent $filewatcher "Changed" -Action $writeaction
    Register-ObjectEvent $filewatcher "Deleted" -Action $writeaction
    Register-ObjectEvent $filewatcher "Renamed" -Action $writeaction
#=====================================================================================================================


    Log -Message "----------------------------------------------------------------------------" -LogFile $LogFile
    Log -Message "Checking if repository for model $($Model.Model) aka $($Model.ProdCode) exists" -LogFile $LogFile
    if (Test-Path "$($RepositoryPath)\$OSVER\$($Model.Model) $($Model.ProdCode)\Repository") { Log -Message "Repository for model $($Model.Model) aka $($Model.ProdCode) already exists" -LogFile $LogFile }
    if (-not (Test-Path "$($RepositoryPath)\$OSVER\$($Model.Model) $($Model.ProdCode)\Repository")) {
        Log -Message "Repository for $($Model.Model) $($Model.ProdCode) does not exist, creating now" -LogFile $LogFile
        New-Item -ItemType Directory -Path "$($RepositoryPath)\$OSVER\$($Model.Model) $($Model.ProdCode)\Repository"
        if (Test-Path "$($RepositoryPath)\$OSVER\$($Model.Model) $($Model.ProdCode)\Repository") {
            Log -Message "$($Model.Model) $($Model.ProdCode) HPIA folder and repository subfolder successfully created" -LogFile $LogFile
            }
        else {
            Log -Message "Failed to create repository subfolder!" -LogFile $LogFile
            Exit
        }
    }
    if (-not (Test-Path "$($RepositoryPath)\$OSVER\$($Model.Model) $($Model.ProdCode)\Repository\.repository")) {
        Log -Message "Repository not initialized, initializing now" -LogFile $LogFile
        Set-Location -Path "$($RepositoryPath)\$OSVER\$($Model.Model) $($Model.ProdCode)\Repository"
        Initialize-Repository
        if (Test-Path "$($RepositoryPath)\$OSVER\$($Model.Model) $($Model.ProdCode)\Repository\.repository") {
            Log -Message "$($Model.Model) $($Model.ProdCode) repository successfully initialized" -LogFile $LogFile
        }
        else {
            Log -Message "Failed to initialize repository for $($Model.Model) $($Model.ProdCode)" -LogFile $LogFile
            Exit
        }
    }    
    
    Log -Message "Set location to $($Model.Model) $($Model.ProdCode) repository" -LogFile $LogFile
    Set-Location -Path "$($RepositoryPath)\$OSVER\$($Model.Model) $($Model.ProdCode)\Repository"
    
    if ($XMLEnableSMTP.Enabled -eq "True")
    {
        Set-RepositoryNotificationConfiguration $SMTP
        Add-RepositorySyncFailureRecipient -to $EMAIL
        Log -Message "Configured notification for $($Model.Model) $($Model.ProdCode) with SMTP: $SMTP and Email: $EMAIL" -LogFile $LogFile
        
    }  
    
    Log -Message "Remove any existing repository filter for $($Model.Model) repository" -LogFile $LogFile
    Remove-RepositoryFilter -platform $($Model.ProdCode) -yes
    
    Log -Message "Applying repository filter for $($Model.Model) repository" -LogFile $LogFile
    if ($XMLCategory1 -eq "True")
    {
           Add-RepositoryFilter -platform $($Model.ProdCode) -os $OS -osver $($Model.OSVER) -category $Category1
           Log -Message "Applying repository filter to $($Model.Model) repository to download: $Category1" -type 1 -LogFile $LogFile

    }
    else
    {
        Log -Message "Not applying repository filter to download $($Model.Model) for: dock" -type 1 -LogFile $LogFile

    }
    if ($XMLCategory2 -eq "True")
    {
        Add-RepositoryFilter -platform $($Model.ProdCode) -os $OS -osver $($Model.OSVER) -category $Category2
        Log -Message "Applying repository filter to $($Model.Model) repository to download: $Category2" -type 1 -LogFile $LogFile

    }
    else
    {
        Log -Message "Not applying repository filter to download $($Model.Model) for: Driver" -type 1 -LogFile $LogFile

    }
    if ($XMLCategory3 -eq "True")
    {
        Add-RepositoryFilter -platform $($Model.ProdCode) -os $OS -osver $($Model.OSVER) -category $Category3
        Log -Message "Applying repository filter to $($Model.Model) repository to download: $Category3" -type 1 -LogFile $LogFile
    }
    else
    {
        Log -Message "Not applying repository filter to download $($Model.Model) for: Firmware" -type 2 -LogFile $LogFile

    }
    if ($XMLCategory4 -eq "True")
    {
        Add-RepositoryFilter -platform $($Model.ProdCode) -os $OS -osver $($Model.OSVER) -category $Category4
        Log -Message "Applying repository filter to $($Model.Model) repository to download: $Category4" -type 2 -LogFile $LogFile

    }
    else
    {
        Log -Message "Not applying repository filter to download $($Model.Model) for: DriverPack" -type 1 -LogFile $LogFile
    }
    
    Log -Message "Invoking repository sync for $($Model.Model) $($Model.ProdCode) repository $os, $($Model.OSVER), $Category1 and $Category2 and $Category3 and $Category4" -LogFile $LogFile
    Invoke-RepositorySync

    Set-RepositoryConfiguration -Setting OfflineCacheMode -CacheValue Enable
    Start-Sleep -s 15
    Set-RepositoryConfiguration -Setting OfflineCacheMode -CacheValue Enable

    Log -Message "Invoking repository cleanup for $($Model.Model) $($Model.ProdCode) repository for $Category1 and $Category2 and $Category3 and $Category4 categories" -LogFile $LogFile
    Invoke-RepositoryCleanup
    Set-RepositoryConfiguration -Setting OfflineCacheMode -CacheValue Enable
    Log -Message "Confirm HPIA files are up to date for $($Model.Model) $($Model.ProdCode) " -LogFile $LogFile 
    $RobocopySource = "$($XMLInstallHPIA.Value)\HPIA Base"
    $RobocopyDest = "$($RepositoryPath)\$OSVER\$($Model.Model) $($Model.ProdCode)"
    $RobocopyArg = '"'+$RobocopySource+'"'+' "'+$RobocopyDest+'"'+' /xc /xn /xo /fft /e /b /copyall'
    $RobocopyCmd = "robocopy.exe"
    Start-Process -FilePath $RobocopyCmd -ArgumentList $RobocopyArg -Wait



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

        New-CMPackage -Name $PackageName -Description $PackageDescription -Manufacturer $PackageManufacturer -Version $PackageVersion -Path $SourcesLocation
        Set-CMPackage -Name $PackageName -DistributionPriority Normal -CopyToPackageShareOnDistributionPoints $True -EnableBinaryDeltaReplication $True
        Start-CMContentDistribution -PackageName  "$PackageName" -DistributionPointGroupName "$DPGroupName"

        $MovePackage = Get-CMPackage -Fast -Name $PackageName
        Move-CMObject -FolderPath $CMFolderPath -InputObject $MovePackage

        Set-Location -Path "$($InstallPath)"
        Log -Message "$PackageName is created in ConfigMgr" -LogFile $LogFile
    }
    Else {
        #Write-Host "Package Already Exist"
        #Write-Host "Updatepackage: $GLOBAL:UpdatePackage"
        If ($GLOBAL:UpdatePackage -eq $True){
            Write-Host "Changes Made: Updating $PackageName" -ForegroundColor Green
            Log -Message "Changes Made: Updating $PackageName on DistributionPoint" -type 2 -LogFile $LogFile
            Update-CMDistributionPoint -PackageName "$PackageName"
        }
        Else {
            Write-Host "No Changes Made, not updating $PackageName" -ForegroundColor Green
             Log -Message "No Changes Made, not updating $PackageName on DistributionPoint" -type 2 -LogFile $LogFile

        }
            Set-Location -Path $($InstallPath)
            Log -Message "Not applying repository filter to download $($Model.Model) for: $Category4" -type 1 -LogFile $LogFile
    }
    
}
Set-Location -Path "$($InstallPath)"
Log -Message "Repository Update Complete" -LogFile $LogFile
Log -Message "----------------------------------------------------------------------------" -LogFile $LogFile