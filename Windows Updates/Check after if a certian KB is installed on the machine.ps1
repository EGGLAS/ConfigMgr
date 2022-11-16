<#
    Author: Nicklas Eriksson
    Created: 2022-02-10
    Purpose: 
    - Check if a certian hotfix is applied on the computer 
#>

$KB = "KB5020435" 

$CheckHotFix = get-hotfix | Where-Object HotFixId -eq $KB | Select-Object *



if ([string]::IsNullOrEmpty($CheckHotFix)) {
    Write-host "Missing"
    
}
else 
{
    $BootTime = Get-CimInstance -ClassName win32_operatingsystem | select csname, lastbootuptime

    $BootTime.lastbootuptime -replace ("/","-") -replace ("-","")

    Write-Host "Installed - $($CheckHotFix.InstalledOn), BootTime: $($BootTime.lastbootuptime)"
}
