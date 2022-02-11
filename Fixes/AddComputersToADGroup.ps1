<#
    Author: Nicklas Eriksson
    Date: 2022-02-10
    Purpose: 
    - Get Computers from a specific ConfigMgr collection 
    - check against an AD-group and removes computers from that AD-group if they are not includede in the collection anymore. 
    - Add computers that are members of the collection to an AD-group

    1.0 - 2022-02-10 - Nicklas Eriksson - Script was created.
    1.1 - 2022-02-10 - NicklaS Eriksson - Updated the script with only add the computers objects that does not exists in the ad-group.
    1.2 - 2022-02-11 - Nicklas Eriksson - Added some error handling and write the output to log file.


    How to run the script:
    .\AddComputersToADGroup.ps1
#>

# Set scriptversion. 
$ScriptVersion = "1.2"

# Custom Variabels
$CollectionID = "CM100000"
$ADGroupName = "TEST"
$ComputerNamePrefix = "TEST*"
$LocalPath = "C:\Temp"
$LogFile = "C:\Temp\AddComputersToLog4jADGroup.log"

# Site configuration
$SiteCode = "CM1" # Site code 
$ProviderMachineName = "server.test.local" # SMS Provider machine name

# Log function
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


$Date = Get-date -Format yyyy-MM-dd_HH-mm

Write-Host "Script was loaded with the following settings:" -ForegroundColor Yellow
Write-Host " - Version: $ScriptVersion" -ForegroundColor Yellow
Write-Host "AD Settings:" -ForegroundColor Yellow
Write-Host " - AD-group: $ADGroupName" -ForegroundColor Yellow
Write-host "ConfigMgr settings:" -ForegroundColor Yellow 
Write-host " - SiteServer: $ProviderMachineName" -ForegroundColor Yellow 
Write-host " - SiteCode: $SiteCode" -ForegroundColor Yellow 
Write-host " - CollectionID: $CollectionID" -ForegroundColor Yellow 

Log -Message "Script was loaded with the following settings:" -type 1 -Component "Script" -LogFile $LogFile
Log -Message " - Version: $ScriptVersion" -type 1 -Component "Script" -LogFile $LogFile
Log -Message "AD settings:" -type 1 -Component "Script" -LogFile $LogFile
Log -Message " - AD-group: $ADGroupName" -type 1 -Component "Script" -LogFile $LogFile
Log -Message "ConfigMgr settings:" -type 1 -Component "Script" -LogFile $LogFile
Log -Message " - SiteServer: $ProviderMachineName" -type 1 -Component "Script" -LogFile $LogFile
Log -Message " - SiteCode: $SiteCode" -type 1 -Component "Script" -LogFile $LogFile
Log -Message " - CollectionID: $CollectionID" -type 1 -Component "Script" -LogFile $LogFile


Write-host "Getting all computers from collection ID: $CollectionID" -ForegroundColor Yellow
Write-host " - Filtering computers that starts with the prefix: $ComputerNamePrefix" -ForegroundColor Yellow

Log -Message "Getting all computers from collection ID: $CollectionID" -type 1 -Component "Script" -LogFile $LogFile
Log -Message " - Filtering computers that starts with the prefix: $ComputerNamePrefix" -type 1 -Component "Script" -LogFile $LogFile

$AllComputers = Get-CMDevice -CollectionId "$CollectionID" -Fast | Where-Object Name -like $ComputerNamePrefix | Select-Object -Property Name
Write-host " - Count computers in the collection: $($AllComputers.count)" -ForegroundColor Yellow
Log -Message " - Count computers in the collection: $($AllComputers.count)" -type 1 -Component "Script" -LogFile $LogFile


# need to set a different location to run AD module.
Set-Location -Path $LocalPath 

# Get AD-group members and select Name from the members.
$CurrentADMembers = Get-ADGroupMember -Identity $ADGroupName | select Name
Write-host "Comparing objects in $CollectionID with AD-group $ADGroupName" -ForegroundColor Yellow
Log -Message "Comparing objects in ConfigMgr $CollectionID with AD-group $ADGroupName" -type 1 -Component "Script" -LogFile $LogFile

$RemoveCompare = Compare-Object -ReferenceObject $AllComputers.Name -DifferenceObject $CurrentADMembers.Name | Where-Object SideIndicator -EQ "=>" | select Inputobject, Sideindicator
$AddToADGroupCompare = Compare-Object -ReferenceObject $AllComputers.Name -DifferenceObject $CurrentADMembers.Name | Where-Object SideIndicator -EQ "<=" | select Inputobject, Sideindicator

if ($RemoveCompare.SideIndicator -eq "=>")
{
    Write-host "Starting to remove $($RemoveCompare.count) computers from AD-group: $ADGroupName" -ForegroundColor Yellow
    Log -Message "Starting to remove $($RemoveCompare.count) computers from AD-group: $ADGroupName" -type 1 -Component "Script" -LogFile $LogFile

    foreach ($RemoveComputerName in $RemoveCompare.InputObject)
    {
       try
       {
            Remove-ADGroupMember -Identity $ADGroupName -Members "$RemoveComputerName$" -Confirm:$false -ErrorAction Stop
            Log -Message " - Successfully removed computer: $RemoveComputerName" -type 1 -Component "Script" -LogFile $LogFile
            Write-host " - Successfully removed computer: $RemoveComputerName" -ForegroundColor Yellow

       }
       catch 
       {
            Write-Host " - Could not remove computer $($RemoveComputerName) from AD-group: $ADGroupName" -ForegroundColor Red
            Write-Host " - Error code: $($_.Exception.Message)" -ForegroundColor Red

            Log -Message " - Could not remove computer $($RemoveComputerName) from AD-group: $ADGroupName" -Type 3 -Component "Error" -LogFile $LogFile
            Log -Message " - Error code: $($_.Exception.Message)" -Type 3 -Component "Error" -LogFile $LogFile

       }
    }
}
else 
{
    Write-host "No computers should be removed from the AD-group: $ADGroupName" -ForegroundColor Yellow
    Log -Message "No computers should be removed from the AD-group: $ADGroupName" -type 1 -Component "Script" -LogFile $LogFile

}


# Will add the computers that does not exists in the ad-group. 
if ($AddToADGroupCompare.SideIndicator -eq "<=")
{
    Write-host "Starting to add $($AddToADGroupCompare.count) computers to AD-group: $ADGroupName" -ForegroundColor Yellow
    Log -Message "Starting to add $($AddToADGroupCompare.count) computers to AD-group: $ADGroupName" -type 1 -Component "Script" -LogFile $LogFile

    foreach ($ComputerName in $AddToADGroupCompare.InputObject)
    {
    
        try
        {
            Add-ADGroupMember -Identity $ADGroupName -Members "$($ComputerName)$" -ErrorAction Stop
            Write-host " - Successfully added computer: $($ComputerName)" -ForegroundColor Yellow
            Log -Message " - Successfully added computer: $($ComputerName)" -type 1 -Component "Script" -LogFile $LogFile

        }
        catch 
        {
                Write-Host " - Could not add $($ComputerName) to the AD-group: $ADGroupName" -ForegroundColor Red
                Write-Host " - Error code: $($_.Exception.Message)" -ForegroundColor Red
            
                Log -Message " - Could not add $($ComputerName) to the AD-group: $ADGroupName" -Type 3 -Component "Error" -LogFile $LogFile
                Log -Message " - Error code: $($_.Exception.Message)" -Type 3 -Component "Error" -LogFile $LogFile

        }
    }

}
else
{
    Write-host "No computers will be added to the AD-group: $ADGroupName" -ForegroundColor Yellow
    Log -Message "No computers will be added to the AD-group: $ADGroupName" -type 1 -Component "Script" -LogFile $LogFile
}

Write-Host "Happy automating the job is now done. (Y)" -ForegroundColor Yellow
Log -Message "Happy automating the job is now done. (Y)" -type 1 -Component "Script" -LogFile $LogFile
Log -Message "---------------------------------------------------------------------------------------------------------------------------------------------------" -type 1 -Component "Script" -LogFile $LogFile