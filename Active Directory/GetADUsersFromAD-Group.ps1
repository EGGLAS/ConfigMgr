<#
  Author: Nicklas Eriksson
  Date: 2022-02-04
  Purpose: Fetching GivenName, Surname ,Name, Mail from AD-group.
  Version: 1.1
  Changelog: 1.0 - 2022-02-04 - Nicklas Eriksson -  Script was created.
             1.1 - 2022-02-05 - Nicklas Eriksson - Updated to check if path exists if not the folder will be created.
  
  How to run it:
  .\GetADUsersFromAD-Group.ps1 -ADGroups "AD-GroupTest" -FilePath "E:\Scripts"
#>

param(
    [Parameter(Mandatory=$True, HelpMessage='Enter AD-group name, support multiple AD-groups')]
    [string[]]$ADGroups,
    [Parameter(Mandatory=$True, HelpMessage='Enter the path ')]
    [string]$FilePath
)

Write-Host "Info: Script started" -ForegroundColor Yellow
$Date = Get-date -Format yyyy-MM-dd_hh-mm

$ADUsers = foreach ($ADGroup in $ADGroups)
        {
            try
            {
                Write-host "Info: Getting all AD-members from AD-group: $ADGroup" -ForegroundColor Yellow
                $ADMembers = Get-ADGroupMember -Identity $ADGroups 

            }
            catch
            {
                Write-Host "ERROR: Could not get any members from AD-group: $ADGroup" -ForegroundColor Red
                break
            }

            Write-host "Info: Starting to get information per user from AD-group: $ADGroup" -ForegroundColor Yellow
            foreach ($ADMember in $ADMembers)
            {
                
                Get-ADUser -Identity $ADMember.SamAccountName -Properties * | Select-Object DisplayName ,Name, Mail
            }             
            
            Write-host "Info: Done with AD-group: $ADGroup" -ForegroundColor Yellow
        }

Write-host "Info: Found $($ADUsers.count) users" -ForegroundColor Yellow



if ((Test-Path -Path $FilePath) -eq $False)
{
    try {
            Write-Host " - Starting to create folder with foldername: $FilePath" -ForegroundColor Yellow
            Write-Host " - Creating folder with foldername: $FilePath" -ForegroundColor Yellow
            New-item -Path $FilePath -ItemType Directory -ErrorAction Stop 
            Write-Host " - Successfully created folder with foldername: $FilePath" -ForegroundColor Yellow

    

    }
    catch {
            Write-Host " - Could not create folder" -ForegroundColor Red
            Write-Host " - Error code: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "Info: Script will terminate" -ForegroundColor Red
            Break
    }

}
else
{
    Write-host "Info: Path $FilePath exists, skipping.." -ForegroundColor Yellow
}


$ADUsers | Export-Csv -Path "$FilePath\AD-groups_$Date.csv" -Encoding UTF8 -NoTypeInformation 


Write-host "Info: Script has completed successfully" -ForegroundColor Yellow