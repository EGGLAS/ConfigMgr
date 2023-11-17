<#
    Name: Nicklas Eriksson
    Created: 2022-09-23
    Purpose: 
    - Get Current user and check if certian .EXE file exists in the users appdata directory. 
    This can be used togehter with ConfigMgr to determain if the application has been installed the correct way.


#>

Function CurrentUser {
     $LoggedInUser = get-wmiobject win32_computersystem | select username
     $LoggedInUser = [string]$LoggedInUser
     $LoggedInUser = $LoggedInUser.split("=")
     $LoggedInUser = $LoggedInUser[1]
     $LoggedInUser = $LoggedInUser.split("}")
     $LoggedInUser = $LoggedInUser[0]
     $LoggedInUser = $LoggedInUser.split("\")
     $LoggedInUser = $LoggedInUser[1]
     Return $LoggedInUser
}

$user = CurrentUser
start-sleep 30
$InstallPath = "C:\Users\$($user)\AppData\Local\Programs\CoSafeWarningSystem"
$FileName = "CoSafe Warning System.exe"
try
{
    $SearchForExeFile = Get-ChildItem -Path $InstallPath -Filter *.exe -ErrorAction Stop | Where-Object Name -EQ $FileName | Select Name
    $CheckIfEXEExists = Test-Path -Path "$InstallPath\$($SearchForExeFile.Name)"

    if (($CheckIfEXEExists))
    {
        Write-host "Installed"
    }
}
catch 
{
    Exit 1
}

