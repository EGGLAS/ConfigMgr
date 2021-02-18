<# Author: Daniel Gråhns
 Date: 2021-02-11
 Purpose: Download Drivers trough MSEndpointMgr webservice.

 Version: 1.0
 Changelog: 1.0 - 2021-02-11 - Daniel Gråhns - Script was created.
            
 To-do: 
 - Support mutiple OS versions in the same script.
 - Write to local log file on the client.

 Credit, inspiration and copy/paste code from: MSEndpointMgr.com
#>
$URI = "https://test.test.lab/ConfigMgrWebService/ConfigMgr.asmx"
$SecretKey = "Enter your secret key here"
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
