<#
    Author: Nicklas Eriksson
    Created: 2022-02-10
    Purpose: 
    - Get Computers from a specific ConfigMgr collection and returning computername.
    - Check against an AD-group and removes computers from that specific AD-group if they are no longer includede in the collection. 
    - Add computers that are members of the collection to the AD-group.
    - Write everything to a logfile.
    - Write if the computer gets added or removed from the AD-group to a csv file.


    1.0 - 2022-02-10 - Nicklas Eriksson - Script was created.
    1.1 - 2022-02-10 - NicklaS Eriksson - Updated the script with only add the computers objects that does not exists in the ad-group.
    1.2 - 2022-02-11 - Nicklas Eriksson - Added some error handling and write the output to log file.
    1.3 - 2022-02-14 - Nicklas Eriksson - Added max logsize for the logfile so it cant grow out of control.
    1.4 - 2022-02-16 - Nicklas Eriksson - Added a CSV function to write the output of which computers that are being 
    added or removed from the ad-group.
    1.5 - 2022-02-16 - Nicklas Eriksson - Added paramters to the script so it will be easier to reuse.

    How to run the script:
     - Change the variables to suit your enivorment and use case. 
    .\AddComputersToLog4jADGroup_param.ps1 -LocalPath "E:\Test" -ADGroupName "Test" -CollectionID "CM100000" -ComputerNamePrefix "Test*" -SiteCode "CM1" -ProviderMachineName "server.test.local" -OutCSVFile True    

#>

Param(
    [Parameter(Mandatory=$True, HelpMessage='Specifiy the path you want to export all the information to')]
    [string]$LocalPath,
    [Parameter(Mandatory=$True, HelpMessage='Enter the name of the ad-group')]
    [string]$ADGroupName,
    [Parameter(Mandatory=$True, HelpMessage='Enter collection id')]
    [string]$CollectionID,
    [Parameter(Mandatory=$False, HelpMessage='Specifiy the prefix, please include *')]
    [string]$ComputerNamePrefix,
    [Parameter(Mandatory=$True, HelpMessage='Specifiy sitecode')]
    [string]$SiteCode,
    [Parameter(Mandatory=$True, HelpMessage='Specifiy the name of the siteserver')]
    [string]$ProviderMachineName,
    [Parameter(Mandatory=$False, HelpMessage='Specify if you want it to be logged to a CSVfile')]
    [ValidateSet("True", "False")]
    $OutCSVFile = "True"

)


# Set scriptversion. 
$ScriptVersion = "1.5"

# Custom Variabels
$LogFile = "$LocalPath" + "\" + "AddComputersTo$($ADGroupName)ADGroup.log"
$CSVFile = "$LocalPath" + "\" + "AddComputersTo$($ADGroupName)ADGroup.csv"
[int]$LogMaxSize = "2621440"
$SizeMB = [System.Math]::Round((($LogMaxSize)/1MB),2) 

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

Function UpdateCSVFile {
    
    $Export | Export-Csv -Path $CSVFile -Encoding UTF8 -NoClobber -Append -NoTypeInformation -ErrorAction Stop
    Write-host " - Updating CSV-file: $CSVFile" -ForegroundColor Yellow
    Log -Message "- Updating CSV-file: $CSVFile" -type 1 -Component "Script" -LogFile $LogFile


}

# Check if log file maximum file size has been reached.
if (Test-Path -Path $LogFile)
{
    if ((Get-Item -Path $LogFile).Length -gt $LogMaxSize)
    {

        try
        {
            Remove-Item -Path $LogFile -Force:$True
            Write-Host "Deleted the old logfile since maximum file size has been reached: $LogMaxSize" -ForegroundColor Yellow
            Log -Message "Deleted the old logfile since maximum file size has been reached: $LogMaxSize" -type 2 -Component "LogFile" -LogFile $LogFile

        }
        catch 
        {
            Write-Host " - Could not delete the logfile: $($LogFile)" -ForegroundColor Red
            Write-Host " - Error code: $($_.Exception.Message)" -ForegroundColor Red

            Log -Message " - Could not delete the logfile: $($LogFile)" -Type 3 -Component "Error" -LogFile $LogFile
            Log -Message " - Error code: $($_.Exception.Message)" -Type 3 -Component "Error" -LogFile $LogFile

        }
    }
}

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

$Date = Get-date -Format yyyy-MM-dd_HH-mm

Write-Host "Script was loaded with the following settings:" -ForegroundColor Yellow
Write-Host " - Version: $ScriptVersion" -ForegroundColor Yellow
Write-Host " - Max Logsize: $SizeMB MB" -ForegroundColor Yellow
Write-Host "Active Directory Settings:" -ForegroundColor Yellow
Write-Host " - AD-group: $ADGroupName" -ForegroundColor Yellow
Write-host "ConfigMgr settings:" -ForegroundColor Yellow 
Write-host " - SiteServer: $ProviderMachineName" -ForegroundColor Yellow 
Write-host " - SiteCode: $SiteCode" -ForegroundColor Yellow 
Write-host " - CollectionID: $CollectionID" -ForegroundColor Yellow 

Log -Message "Script was loaded with the following settings:" -type 1 -Component "Script" -LogFile $LogFile
Log -Message " - Version: $ScriptVersion" -type 1 -Component "Script" -LogFile $LogFile
Log -Message " - Max Logsize: $SizeMB MB" -type 1 -Component "Script" -LogFile $LogFile
Log -Message "Active Directory settings:" -type 1 -Component "Script" -LogFile $LogFile
Log -Message " - AD-group: $ADGroupName" -type 1 -Component "Script" -LogFile $LogFile
Log -Message "ConfigMgr settings:" -type 1 -Component "Script" -LogFile $LogFile
Log -Message " - SiteServer: $ProviderMachineName" -type 1 -Component "Script" -LogFile $LogFile
Log -Message " - SiteCode: $SiteCode" -type 1 -Component "Script" -LogFile $LogFile
Log -Message " - CollectionID: $CollectionID" -type 1 -Component "Script" -LogFile $LogFile


Write-host "Fetching all computers from collection ID: $CollectionID" -ForegroundColor Yellow
Write-host " - Filtering computers that starts with the prefix: $ComputerNamePrefix" -ForegroundColor Yellow

Log -Message "Fetching all computers from collection ID: $CollectionID" -type 1 -Component "Script" -LogFile $LogFile
Log -Message " - Filtering computers that starts with the prefix: $ComputerNamePrefix" -type 1 -Component "Script" -LogFile $LogFile

$AllComputers = Get-CMDevice -CollectionId "$CollectionID" -Fast | Where-Object Name -like $ComputerNamePrefix | Select-Object -Property Name
Write-host " - Computer count in the collection: $($AllComputers.count)" -ForegroundColor Yellow
Log -Message " - Computer count in the collection: $($AllComputers.count)" -type 1 -Component "Script" -LogFile $LogFile

# Need to set a different location to run AD module.
Set-Location -Path $LocalPath 

try
{
    Write-host "Retriving members from AD-group: $ADGroupName" -ForegroundColor Yellow
    Log -Message "Retriving members from AD-group: $ADGroupName" -type 1 -Component "Script" -LogFile $LogFile

    # Get AD-group members and select Name from the members.
    $CurrentADMembers = Get-ADGroupMember -Identity $ADGroupName -ErrorAction Stop | select Name
    Write-host " - Successfully found $($CurrentADMembers.Count) members in the group" -ForegroundColor Yellow
    Log -Message " - Successfully found $($CurrentADMembers.Count) members in the group" -type 1 -Component "Script" -LogFile $LogFile
}
catch 
{
    Write-Host " - Could not retrive AD-group: $ADGroupName" -ForegroundColor Red
    Write-Host " - Error code: $($_.Exception.Message)" -ForegroundColor Red

    Log -Message " - Could not retrive AD-group: $ADGroupName" -Type 3 -Component "Error" -LogFile $LogFile
    Log -Message " - Error code: $($_.Exception.Message)" -Type 3 -Component "Error" -LogFile $LogFile

}

Write-host "Comparing objects with ConfigMgr collection id $CollectionID and with AD-group $ADGroupName" -ForegroundColor Yellow
Log -Message "Comparing objects with ConfigMgr collection id $CollectionID and with AD-group $ADGroupName" -type 1 -Component "Script" -LogFile $LogFile
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
        # Write computername to CSV-file.
        if ($OutCSVFile -eq "True")
        {
            try
            {
                # Creating a custom PSTable
                $Export = [pscustomobject]@{
                ComputerName = $RemoveComputerName
                Date = Get-date -Format "yyyy-MM-dd hh:mm"      
                Vulnerable = "No"
            }
            
                UpdateCSVFile
        }
        catch 
        {
                Write-Host " - Could not update csvfile : $CSVFile" -ForegroundColor Red
                Write-Host " - Error code: $($_.Exception.Message)" -ForegroundColor Red
            
                Log -Message " - Could not update csvfile : $CSVFile" -Type 3 -Component "Error" -LogFile $LogFile
                Log -Message " - Error code: $($_.Exception.Message)" -Type 3 -Component "Error" -LogFile $LogFile
        }

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
    Write-host "Starting to add $($AddToADGroupCompare.Count) computers to AD-group: $ADGroupName" -ForegroundColor Yellow
    Log -Message "Starting to add $($AddToADGroupCompare.Count) computers to AD-group: $ADGroupName" -type 1 -Component "Script" -LogFile $LogFile

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
        
        # Out computername to CSV-file.
        if ($OutCSVFile -eq "True")
        {
        try
        {
            # Creating a custom PSTable
            $Export = [pscustomobject]@{
            ComputerName = $ComputerName
            Date = Get-date -Format "yyyy-MM-dd hh:mm"      
            Vulnerable = "Yes"
            }
            
            UpdateCSVFile

        }
        catch 
        {
                Write-Host " - Could not update csvfile : $CSVFile" -ForegroundColor Red
                Write-Host " - Error code: $($_.Exception.Message)" -ForegroundColor Red
            
                Log -Message " - Could not update csvfile : $CSVFile" -Type 3 -Component "Error" -LogFile $LogFile
                Log -Message " - Error code: $($_.Exception.Message)" -Type 3 -Component "Error" -LogFile $LogFile
        }

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