<#
 Author: Nicklas Eriksson
 Purpose: Add computers to collection by ID or name.
 Created: 2022-10-19
 Latest updated: 2022-11-04
 Current Version: 1.2
 Changelog: 1.0 - 2022-10-19 - Nicklas Eriksson -  Script was created.
            1.1 - 2022-10-10 - NicklaS Eriksson - Added support for single computer and collection name.
            1.2 - 2022-11-04 - Nicklas Eriksson - Updated script to support multiple computers when adding single computers.

 How run the script:
  Create a text file that specify the path where the text file exists, adding multiple computers from text file to the collection by ID. 
 .\AddComptuersToCollectionByID.ps1 -SiteCode LO2 -SiteServer siteserver.domain.local -CollectionID LO1000X3 -ComputerFile E:\Scripts\Computers.txt
 Enter a single computer to add to the collection by ID.
  .\AddComptuersToCollectionByID.ps1 -SiteCode LO2 -SiteServer siteserver.domain.local -CollectionID LO1000X3 -Computer "Test1000"
 Enter multiple computers to add to the collection by Name
 .\AddComptuersToCollectionByID.ps1 -SiteCode LO2 -SiteServer siteserver.domain.local -CollectionName "Test computers IT" -ComputerName "Test1000","Test10001"

#>


[CmdletBinding(DefaultParameterSetName = "")]
param(
    [Parameter(Mandatory=$True, HelpMessage='Specify sitecode.')]
    [string]$SiteCode,
    [Parameter(Mandatory=$True, HelpMessage='Specify siteserver.')]
    [string]$SiteServer,
    [Parameter(Mandatory=$False, HelpMessage='Specify collectionID.')]
    [string]$CollectionID,
    [Parameter(Mandatory=$False, HelpMessage='Specify the name of the collection.')]
    [string]$CollectionName,
    [Parameter(Mandatory=$False, HelpMessage='Specify path to the csv-file that contains computer.')]
    [string]$ComputerFile,
    [Parameter(Mandatory=$False, HelpMessage='Enter computername.')]
    [string[]]$ComputerName  
)

$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition

if ([string]::IsNullOrEmpty($ComputerFile)) {
        Write-host "Info: Text file is not specified, variable Computername was specified, will add $($ComputerName) to the collection" -Foregroundcolor Yellow
    $Computers = $ComputerName

}
else {
    Write-host "Info: Fetching computers from file: $($ComputerFile)" -ForegroundColor Yellow
    $Computers = Get-content -path $ComputerFile 

}

# Site configuration
$ProviderMachineName = $SiteServer # SMS Provider machine name
$SleepTimer = 30

# Customizations
$initParams = @{}
#$initParams.Add("Verbose", $true) # Uncomment this line to enable verbose logging
#$initParams.Add("ErrorAction", "Stop") # Uncomment this line to stop the script on any errors

# Do not change anything below this line

# Import the ConfigurationManager.psd1 module 
if((Get-Module ConfigurationManager) -eq $null) {
    Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" @initParams 
}

# Connect to the site's drive if it is not already present
if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName @initParams
}

# Set the current location to be the site code.
Set-Location "$($SiteCode):\" @initParams


# Get CollectionID if CollectionName was specified.
if ([string]::IsNullOrEmpty($CollectionName)) {
    
    Write-host "Info: CollectionID was specified, no need to get the information." -Foregroundcolor Yellow

}
else {
    
    Write-host "Info: Fetching colletionid from collectionname: $($CollectionName)" -ForegroundColor Yellow
    $CollectionID = Get-CMCollection -Name $CollectionName -ErrorAction Stop  | Select-Object -ExpandProperty CollectionID
    
    # Check if CollectionID contains something, tried with catch step but could not get that to work.
    if ([string]::IsNullOrEmpty($CollectionID))
    {
        Write-host "Error: Something went wrong, could not get collectionID from $($CollectionName)" -ForegroundColor Red
        Break
    }
   
    Write-host "Info:  - Found collectionid from Name: $CollectionID" -ForegroundColor Yellow
}


Write-host "Info: Starting to add Computers to CollectionID: $($CollectionID)" -ForegroundColor Yellow
foreach ($Computer in $Computers)
{
    try {
        $ResourceID = Get-CMDevice -Name "$($Computer)" -fast -ErrorAction Stop | Select-object -ExpandProperty ResourceID
        Write-host "Info: - Adding $($Computer) to $CollectionID" -ForegroundColor Yellow
        Add-CMDeviceCollectionDirectMembershipRule -CollectionId "$collectionID" -ResourceId $ResourceID
    
    }
    catch
    {
        Write-Host "ERROR: Could not add $($Computer) to the collection: $($CollectionID)" -ForegroundColor Red
        Write-Host " - Error code: $($_.Exception.Message)" -ForegroundColor Red

    }
}

Write-Host "Info: Trigger update on the collection" -ForegroundColor Yellow
$CollectionDate = Get-CMCollectionFullEvaluationStatus -id $collectionID | Select-Object -ExpandProperty LastRefreshTime
Invoke-CMCollectionUpdate -CollectionId $collectionID

Write-Host "Info: Checking every $($SleepTimer) second if collection has been refreshed" -ForegroundColor Yellow
# Sleep until collection has beeen updated.
do
{
    Write-host " - Info: Collection $($collectionID) has not been refreshed yet" -ForegroundColor Yellow
    Start-Sleep $SleepTimer
    $CheckIfCollectionIsRefreshed = Get-CMCollectionFullEvaluationStatus -id $collectionID | Select-Object -ExpandProperty LastRefreshTime
    
}
until ($CollectionDate -ne $CheckIfCollectionIsRefreshed)

Write-host "Info: Collection has been updated" -ForegroundColor Yellow
Write-host "Info: Trigger machine policy on collectionID: $collectionID" -ForegroundColor Yellow
Invoke-CMClientAction -CollectionId $collectionID -ActionType ClientNotificationRequestMachinePolicyNow

Set-Location -Path $scriptPath

Write-host "Info: Job is done" -ForegroundColor Green
