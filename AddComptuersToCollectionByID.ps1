<#
 Author: Nicklas Eriksson
 Purpose: Add computers to collection by ID.
 Created: 2022-10-19
 Latest updated: 2022-10-19
 Current Version: 1.0
 Changelog: 1.0 - 2022-10-19 - Nicklas Eriksson -  Script was created.

 How run the script:
 .\AddComptuersToCollectionByID.ps1 -SiteCode LO2 -SiteServer siteserver.domain.local -CollectionID LO1000X3 -ComputerFile E:\Scripts\Computers.txt

#>


[CmdletBinding(DefaultParameterSetName = "")]
param(
    [Parameter(Mandatory=$True, HelpMessage='Specify sitecode.')]
    [string]$SiteCode,
    [Parameter(Mandatory=$True, HelpMessage='Specify siteserver.')]
    [string]$SiteServer,
    [Parameter(Mandatory=$True, HelpMessage='Specify collectionID.')]
    [string]$CollectionID,
    [Parameter(Mandatory=$True, HelpMessage='Specify csv-file.')]
    [string]$ComputerFile 
)

Write-host "Fetching computers from file: $($ComputerFile)" -ForegroundColor Yellow
$Computers = Get-content -path $ComputerFile 

# Site configuration
$ProviderMachineName = $SiteServer # SMS Provider machine name

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

Write-host "Starting to add Computers to CollectionID: $($CollectionID)" -ForegroundColor Yellow
foreach ($Computer in $Computers)
{
    $ResourceID = Get-CMDevice -Name "$($Computer)" -fast -ErrorAction Stop | Select -ExpandProperty ResourceID
    Write-host "Adding $($Computer) to $CollectionID" -ForegroundColor Yellow
    Add-CMDeviceCollectionDirectMembershipRule -CollectionId "$collectionID" -ResourceId $ResourceID
}

$CollectionDate = Get-CMCollectionFullEvaluationStatus -id $collectionID | Select -ExpandProperty LastRefreshTime
Invoke-CMCollectionUpdate -CollectionId $collectionID

# Sleep until collection has beeen updated.
do
{
    Start-Sleep 1
    $CheckIfCollectionIsRefreshed = Get-CMCollectionFullEvaluationStatus -id $collectionID | Select -ExpandProperty LastRefreshTime
    Write-host "Collection $($collectionID) has not been refreshed yet" -ForegroundColor Yellow

    
}
until ($CollectionDate -ne $CheckIfCollectionIsRefreshed)

Write-host "Trigger machine policy on collectionID: $collectionID" -ForegroundColor Yellow
Invoke-CMClientAction -CollectionId $collectionID -ActionType ClientNotificationRequestMachinePolicyNow
Write-host "Job is done" -ForegroundColor Yellow
