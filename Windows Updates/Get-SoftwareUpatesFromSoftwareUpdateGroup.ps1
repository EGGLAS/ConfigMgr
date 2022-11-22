<#
 Name: Nicklas Eriksson
 Date: 2022-11-21
 Purpose: Fetching GivenName, Surname ,Name, Mail from AD-group.
 Version: 1.0
 Changelog: 1.0 - 2022-02-04 - Nicklas Eriksson -  Script was created.

 How to run it:
 .\AddComptuersToCollectionByID.ps1 -SiteCode LO2 -SiteServer siteserver.domain.local


#>

param(
    [Parameter(Mandatory=$True, HelpMessage='Specify sitecode.')]
    [string]$SiteCode,
    [Parameter(Mandatory=$True, HelpMessage='Specify siteserver.')]
    [string]$SiteServer
)

$SoftwareUpdateRule = "ADR: Windows Server*"
$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition

# Site configuration
$SiteCode = $SiteCode # Site code 
$ProviderMachineName = $SiteServer # SMS Provider machine name

# Customizations
$initParams = @{}

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
    Write-host "Getting Software updates from Software Updategroup: $($SoftwareUpdateRule)"
    $GetSoftwareUpdates = Get-CMSoftwareUpdateGroup | where-object LocalizedDisplayName -like $SoftwareUpdateRule  | Select-object *
    Write-host "Found: $($GetSoftwareUpdates.Count)"
    Write-host "The following Software Update groups were found"

   foreach ($SoftwareUpdateGroup in $GetSoftwareUpdates)
   {
       Write-host " - Name: $($SoftwareUpdateGroup.LocalizedDisplayName)"
   }

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
        Write-host "Checking Software Updategroup: $($update)" -ForegroundColor Yellow
        Get-CMSoftwareUpdate -UpdateGroupName $Update -fast | Select-object -expandproperty LocalizedDisplayName
        Write-host "----------------------------------------------------------------------------------------" -ForegroundColor Yellow
    }
}

Set-Location -Path $scriptPath