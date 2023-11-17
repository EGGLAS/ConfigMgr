<#
    Name: Nicklas Eriksson
    Purpose: Gather logs from Eventviewer between dates and exporting the information to an CSV-file on user desktop. 
    
    You running this script/function means you will not blame the author(s) if this breaks your stuff. This script/function is provided AS IS without warranty of any kind. The entire risk arising out of the use or performance of the sample scripts and documentation remains with you. 
    In no event shall author(s) be held liable for any damages whatsoever (including, without limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary loss) arising out of the use of or inability to use the script or documentation. 
    Simply put: Use at your own risk.
#>

Param(
    [Parameter(Mandatory=$True, HelpMessage='How many days back do you want to export logs entries for?')]
    [ValidateScript({$_ -gt 0})]
    [int]$DaysBack = 1

)


$Date = Get-Date # Get current date
$CSVFileName = "EventViewer_$(Get-date -Format yyyy_MM_dd_HH_ss).csv" # Set CSV-filename and construct it with current date and time
$CSVFullPath = "$($Env:USERPROFILE)\Desktop\test\$CSVFileName" # Construct fullpath to CSV-file.

# Gathering eventlogs based from folder 'System' and between two dates.
Write-host "Gathering eventlogs from logfolder 'System' between $($Date.AddDays(-$DaysBack)) to $($Date)" -ForegroundColor Cyan
$GetAllEventLogs = Get-EventLog -LogName System -After $Date.AddDays(-1) -InstanceId 16 -ErrorAction Stop

# Filter out only certian event logs based on instance id.
<#
# Create an array 
$FilterdEventLogs = @()

foreach ($SingleEventLog in $GetAllEventLogs)
{
    if (($SingleEventLog.instanceid -eq "16") -or ($SingleEventLog.instanceid -eq "507"))
    {
        $FilterdEventLogs += $SingleEventLog
    }
    else {

    }
}
#>

Write-host " - Successfully gathered eventlogs from logfolder 'System'" -ForegroundColor Cyan

# Exporting CSV-file
Write-Host "Exporting CSV-File to: $CSVFullPath" -ForegroundColor Cyan
$GetAllEventLogs | Export-Csv -Path $CSVFullPath -Encoding UTF8 -ErrorAction Stop
Write-host " - Successfully created CSV-file" -ForegroundColor Cyan


