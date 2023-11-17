

$CSVFile = "C:\temp\CSV_computers.csv"
$ComputerPath = "C:\temp\computers.txt"
$File = Get-Content -Path $ComputerPath

$AllComputers = $File 

$InfoAboutComputers = @()

foreach ($SingleComputer in $AllComputers)
{
    Write-host "Looking up computer: $SingleComputer"
    $GetADComputer = Get-ADComputer -Identity $SingleComputer -Properties Name,DistinguishedName, Operatingsystem  | Select-Object Name,DistinguishedName, Operatingsystem

    $InfoAboutComputers += $GetADComputer
}

$InfoAboutComputers | Sort-Object Name -Descending | Format-Table 

$InfoAboutComputers | Export-Csv -Path $CSVFile -NoTypeInformation -Encoding UTF8