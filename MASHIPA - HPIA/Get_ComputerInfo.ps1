<# Name: Nicklas Eriksson
   Date: 2021-06-21
   Purpose: Get Baseboard and computersystem for HPIA.
  
#>

Write-host "After computersystem has been typed out, and you press any key powershell window will close....." -ForegroundColor Yellow
Write-host "Info: Getting Baseboard and Computermodel for local computer"
$Baseboard = (Get-CimInstance -ClassName win32_baseboard).Product
$Computersystem = (Get-CimInstance -ClassName win32_computersystem).Model

Write-host ("Baseboard: $Baseboard")
Write-host ("Model: $Computersystem")
Write-Host -Object ('The key that was pressed was: {0}' -f [System.Console]::ReadKey().Key.ToString());