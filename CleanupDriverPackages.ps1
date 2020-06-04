# Name: Nicklas Eriksson, IT-center
# 
# Purpose: Cleanup all drivers that are marked as retired in Configuration Manager and deletes sourcefiles.
# Version: 1.0 - 2020-06-03
# History: 1.0 - 2020-06-03: Script was created.
# 1.1 - 2020-06-04: Logfile was added and send to teams channel.
# To-do: Create logfile to see what have been deleted in the past.

# Uncomment the line below if running in an environment where script signing is 
# required.
# Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process

# Script version
$ScriptVersion = "1.1" # 2020-06-03

# Variabels 
$Location = "C:\"
$DriverPackageName = "Drivers Retired*"
$LogFile = "E:\Scripts\CleanupDriverPackages.log"
[int]$MaxLogSize = 2621440

# Teams variabels 
$Teams = "NO" # Send notfiaction to Teams or change to No.
$uri = 'https://outlook.office.com/webhook/e757a656-1fb0-4ad9-b8e0-15e7695d69ac@452aa124-31b2-4f44-9f43-e2d1fd785043/IncomingWebhook/980203479aba42269ae194e0b1202774/1dedfcec-2a99-4c48-bd7d-5e0f2710f953'
$Logo = 'https://www.ludvika.se/images/18.3a3ae1661636381356a1054/1526390491896/ludvika_logo.png' # this value would be a path to a nice image you would like to display in notifications

# Site configuration
$SiteCode = "CM1" # Site code 
$ProviderMachineName = "LKSRVSCCM03.res.ludvika.intra" # SMS Provider machine name

# Customizations
$initParams = @{}



Function Add-TextToCMLog {
##########################################################################################################
<#
.SYNOPSIS
   Log to a file in a format that can be read by Trace32.exe / CMTrace.exe 
 
.DESCRIPTION
   Write a line of data to a script log file in a format that can be parsed by Trace32.exe / CMTrace.exe
 
   The severity of the logged line can be set as:
 
        1 - Information
        2 - Warning
        3 - Error
 
   Warnings will be highlighted in yellow. Errors are highlighted in red.
 
   The tools to view the log:
 
   SMS Trace - http://www.microsoft.com/en-us/download/details.aspx?id=18153
   CM Trace - Installation directory on Configuration Manager 2012 Site Server - <Install Directory>\tools\
 
.EXAMPLE
   Add-TextToCMLog c:\output\update.log "Application of MS15-031 failed" Apply_Patch 3
 
   This will write a line to the update.log file in c:\output stating that "Application of MS15-031 failed".
   The source component will be Apply_Patch and the line will be highlighted in red as it is an error 
   (severity - 3).
 
#>
##########################################################################################################
 
    #Define and validate parameters
    [CmdletBinding()]
    Param(
          #Path to the log file
          [parameter(Mandatory=$True)]
          [String]$LogFile,
 
          #The information to log
          [parameter(Mandatory=$True)]
          [String]$Value,
 
          #The source of the error
          [parameter(Mandatory=$True)]
          [String]$Component,
 
          #The severity (1 - Information, 2- Warning, 3 - Error)
          [parameter(Mandatory=$True)]
          [ValidateRange(1,3)]
          [Single]$Severity
          )
 
 
    #Obtain UTC offset
    $DateTime = New-Object -ComObject WbemScripting.SWbemDateTime 
    $DateTime.SetVarDate($(Get-Date))
    $UtcValue = $DateTime.Value
    $UtcOffset = $UtcValue.Substring(21, $UtcValue.Length - 21)
 
 
    #Create the line to be logged
    $LogLine =  "<![LOG[$Value]LOG]!>" +`
                "<time=`"$(Get-Date -Format HH:mm:ss.fff)$($UtcOffset)`" " +`
                "date=`"$(Get-Date -Format M-d-yyyy)`" " +`
                "component=`"$Component`" " +`
                "context=`"$([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)`" " +`
                "type=`"$Severity`" " +`
                "thread=`"$($pid)`" " +`
                "file=`"`">"
 
    #Write the line to the passed log file
    Out-File -InputObject $LogLine -Append -NoClobber -Encoding Default -FilePath $LogFile -WhatIf:$False
 
}


#If the log file exists and is larger then the maximum then roll it over.
If (Test-path  $LogFile -PathType Leaf) {
    If ((Get-Item $LogFile).length -gt $MaxLogSize){
        Move-Item -Force $LogFile ($LogFile -replace ".$","_") -WhatIf:$False
    }
}

# Script starts here
Add-TextToCMLog $LogFile "<--------------------------------------------------------------------------------------------------------------------->"  -Component "Start" -Severity 1
Add-TextToCMLog $LogFile "Powershellscript was started with scriptversion: $($ScriptVersion)" -Component "Powershell" -Severity 1 

# Do not change anything below this line

# Import the ConfigurationManager.psd1 module 
if((Get-Module ConfigurationManager) -eq $null) {
    Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" @initParams 
}

# Connect to the site's drive if it is not already present
if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName @initParams
}

# Gett current script location
$GetCurrentLocation = Get-Location

# Set the current location to be the site code.
Set-Location "$($SiteCode):\" @initParams

# Get all CM packages with fast channel.
Add-TextToCMLog $LogFile "Getting all packages that are marked as $($DriverpackageName)" -Component "Powershell" -Severity 1

$AllRetiredDriverPackage = Get-CMPackage -Name $DriverPackageName -fast #| Select-Object -Property Name, pkgSourcePath
Add-TextToCMLog $LogFile "Got $($AllRetiredDriverPackage.count) packages that was marked for deletion." -Component "Powershell" -Severity 1

# Delete Packages in ConfigMgr
Foreach($RetiredCMPackage in $AllRetiredDriverPackage)
{
    Add-TextToCMLog $LogFile "Starting to remove $($RetiredCMPackage.Name)." -Component "Powershell" -Severity 1
    Remove-CMPackage -Name $RetiredCMPackage.Name -Force -Verbose -WhatIf
    Write-host "Successfully removed $($RetiredCMPackage.Name) ConfigMgr Package" -ForegroundColor DarkGreen
    Add-TextToCMLog $LogFile "Successfully removed $($RetiredCMPackage.Name)." -Component "Powershell" -Severity 1

}

# Delete source folders
foreach ($RetiredCMPackage in $AllRetiredDriverPackage)
{
    $DeleteRetiredPackagePath = $RetiredCMPackage.PkgSourcePath -replace "\\StandardPkg\\" -replace ""
    Add-TextToCMLog $LogFile "Starting to remove $($RetiredCMPackage.Name) with sourcepath $($DeleteRetiredPackagePath) ." -Component "Powershell" -Severity 1
    Set-Location -Path $Location # Must set a new Location since it will not find any source files on the network share since you are on ConfigMgr PSDrive
    Remove-item -Path $DeleteRetiredPackagePath -Verbose -Confirm:$false -Recurse -WhatIf
    Write-host "Successfully removed $($RetiredPackage.Name) source files" -ForegroundColor DarkGreen
    Add-TextToCMLog $LogFile "Successfully removed $($RetiredCMPackage.Name) with sourcepath $($DeleteRetiredPackagePath) ." -Component "Powershell" -Severity 1
}

Set-Location -path $GetCurrentLocation


# Send notifaciton to Teams 
if ($Teams -eq "YES")
{
        # Date and Time
    $DateTime = Get-Date -Format g #Time

    # these values would be retrieved from or set by an application

    $body = ConvertTo-Json -Depth 4 @{
      title    = "IT-Center Automation tool"
      text	 = "Clean-up bot reports status:"
      sections = @(
        @{
          activityTitle    = 'Clean-up job for Driver Automation Tool'
          activitySubtitle = "$DateTime"
          #activityText	 = ' '
          activityImage    = "$Logo"
        },
        @{
          title = '<h2 style=color:blue;>Status:'
          facts = @(
            @{
              name  = 'ConfigMgr Packages marked for deletion'
              value = "$($AllRetiredDriverPackage.count)"
            },
            @{
              name  = 'Logfile Path:'
              value = "$($env:COMPUTERNAME), $LogFile"        
            }
          )
        }
      )
    }

    Invoke-RestMethod -uri $uri -Method Post -body $body -ContentType 'application/json'

}

if ($AllRetiredDriverPackage.count -gt "0")
{
   Add-TextToCMLog $LogFile "Successfully removeded all packages $($AllRetiredDriverPackage.count) and the sourcepath." -Component "Powershell" -Severity 1
   Add-TextToCMLog $LogFile "Script has completed" -Component "End" -Severity 1
   Add-TextToCMLog $LogFile "<--------------------------------------------------------------------------------------------------------------------->" -Component "End" -Severity 1

}
else
{
   Add-TextToCMLog $LogFile "$($AllRetiredDriverPackage.count) packages was marked for deletion." -Component "End" -Severity 1
   Add-TextToCMLog $LogFile "Script has completed" -Component "End" -Severity 1
   Add-TextToCMLog $LogFile "<--------------------------------------------------------------------------------------------------------------------->" -Component "End" -Severity 1
}