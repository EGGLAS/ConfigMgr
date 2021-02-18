$URI = "https://test.test.lab/ConfigMgrWebService/ConfigMgr.asmx"
$SecretKey = ""
$Filter = "HPIA-20H2-" + (Get-WmiObject -Class:Win32_ComputerSystem).Model + " " + (Get-WmiObject -Class:Win32_BaseBoard).Product

try {
        $WebService = New-WebServiceProxy -Uri $URI -ErrorAction Stop
        $Packages = $WebService.GetCMPackage($SecretKey, $Filter) 
        $PackageID = $Packages.PackageID
                             }
                             catch [System.Exception] {
                             }

# Construct TSEnvironment object
try {
    $TSEnvironment = New-Object -ComObject Microsoft.SMS.TSEnvironment -ErrorAction Stop
}
catch [System.Exception] {
    Write-Warning -Message "Unable to construct Microsoft.SMS.TSEnvironment object" ; exit 3
}


$TSEnvironment.value("OSDDownloadDestinationLocationType") = "CCMCache"
$TSEnvironment.value("OSDDownloadContinueDownloadOnError") = "1"
$TSEnvironment.value("OSDDownloadDownloadPackages") = "$PackageID"
$TSEnvironment.value("OSDDownloadDestinationVariable") = "SOFTPAQ"
