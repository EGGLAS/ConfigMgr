# Name: Nicklas Eriksson
# 
# Purpose: Change all Moder Driver mangement package that has the name Hewlett-Packard in manufacturer field to HP.
# Version: 1.0 - 2020-09-18
# History: 1.0 - 2020-09-18: Script was created.

# Variabels 
$SiteCode = "CM1" # Site code 
$ProviderMachineName = "CM.Domain.Local" # SMS Provider machine name
$DriverPackageName = "Drivers - HP*" # Control which package you want to change. In my exemple I want to change all HP Drivers that start with the Name Drivers - HP
$Manufacturer = "HP" # 

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

$AllRetiredDriverPackage = Get-CMPackage -Name $DriverPackageName -fast #| Select-Object -Property Name, pkgSourcePath

if ($AllRetiredDriverPackage.Manufacturer -eq "Hewlett-Packard")
{
    write-host "Starting to change Package manufacturer to HP from Hewlett-Packard" -ForegroundColor Yellow
    foreach ($HP in $AllRetiredDriverPackage)
    {
    Set-CMPackage -Name $HP.Name -Manufacturer "$Manufacturer" -verbose
    }
}
else
{
    Write-host "No Package found to change" -ForegroundColor Green
}
