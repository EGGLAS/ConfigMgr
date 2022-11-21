<#
 Name: Nicklas Eriksson
 Date: 2022-11-21
 Purpose: Getting software updates from Software Update group.
 Version: 1.0
 Changelog: 1.0 - 2022-02-04 - Nicklas Eriksson -  Script was created.

 How to run it:
 Change variable $SoftwareUpdateRule to suit your environment. 

 .\Get-SoftwareUpatesFromSoftwareUpdateGroup.ps1 -SiteCode LO2 -SiteServer siteserver.domain.local

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

$SoftwareUpdateRule = "ADR: Windows Server*" # Change this to suit your environment
$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition

# Site configuration
$SiteCode = $SiteCode # Site code 
$ProviderMachineName = $SiteServer # SMS Provider machine name

# Customizations
$initParams = @{}
#$initParams.Add("Verbose", $true) # Uncomment this line to enable verbose logging
#$initParams.Add("ErrorAction", "Stop") # Uncomment this line to stop the script on any errors

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

# Get Software update group based on variable $SoftwareUpdateRule
try {
    Write-host "Getting Software updates for Software Updategroup: $($SoftwareUpdateRule)"
    $GetSoftwareUpdates = Get-CMSoftwareUpdateGroup | where-object LocalizedDisplayName -like $SoftwareUpdateRule  | Select-object *

}
catch
{
    Write-Host "ERROR: Could not get Software Updates from  $($CollectionID)" -ForegroundColor Red
    Write-Host " - Error code: $($_.Exception.Message)" -ForegroundColor Red
    Set-Location -Path $scriptPath
    Break
}

# Get Software updates from each Software update group.
if ([string]::IsNullOrEmpty($GetSoftwareUpdates)) {
        Write-host "Something went wrong when fetching Software update group/s" -Foregroundcolor Red
        Set-Location -Path $scriptPath
        Break
}
else {
    foreach ($update in $GetSoftwareUpdates.LocalizedDisplayName)
    {
        Write-host "Getting Software updates from Software Updategroup: $($SoftwareUpdateRule)"
        Get-CMSoftwareUpdate -UpdateGroupName $Update -fast | Select-object -expandproperty LocalizedDisplayName
        Write-host "----------------------------------------------------------------------------------------" -ForegroundColor Yellow
    }
}

Set-Location -Path $scriptPath