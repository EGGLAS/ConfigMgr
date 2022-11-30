<#
 Name: Nicklas Eriksson
 Date: 2022-11-21
 Purpose: Getting software updates from Software Update group. 
 Version: 1.0
 Changelog: 1.0 - 2022-11-21 - Nicklas Eriksson -  Script was created.
            1.1 - 2022-11-21 - Nicklas Eriksson -  Updated the script with the paramter RunADR, it's now possible to run the ADRs again if some updates are missing. .

 How to run it:
 This will get all updates from all Software update groups that starts with the name ADR: Windows Server.
 .\Get-SoftwareUpatesFromSoftwareUpdateGroup.ps1 -SiteCode LO2 -SiteServer siteserver.domain.local
 This will get all updates from all Software update groups that starts with the name ADR: Windows Server and run the ADRs again if some update is missing.
 .\Get-SoftwareUpatesFromSoftwareUpdateGroup.ps1 -SiteCode LO2 -SiteServer siteserver.domain.local -RunADR



#>

param(
    [Parameter(Mandatory=$True, HelpMessage='Specify sitecode.')]
    [string]$SiteCode,
    [Parameter(Mandatory=$True, HelpMessage='Specify siteserver.')]
    [string]$SiteServer,
    [Parameter(Mandatory=$False, HelpMessage='Run Automatic Deployment Rules.')]
    [switch]$RunADR
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
    Write-host "Getting all Software Update groups that starts with the following names: $($SoftwareUpdateRule)"
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


if ($RunADR)
{
    Write-host "Getting all ADRs that should be triggerd" -ForegroundColor Yellow
    $GetAllADR = Get-CMSoftwareUpdateAutoDeploymentRule -fast | where-object Name -like $SoftwareUpdateRule  | Select-object Name
    Write-host "The following Automatic Deployment Rules will be triggerd." -ForegroundColor Yellow
       foreach ($ADR in $GetAllADR.Name)
   {
       Write-host " - Name: $($ADR)"
   }

    Write-host "The following Automatic Deployment Rules will be triggerd." -ForegroundColor Yellow

    foreach ($ADR in $GetAllADR.Name)
    {
        Invoke-CMSoftwareUpdateAutoDeploymentRule -Name $ADR -WhatIf
        Write-host " - $($ADR) was triggerd to run" -ForegroundColor Yellow
    }
}
else
{

    Write-host "ADRs was not schedulde to be updated."

}


Set-Location -Path $scriptPath