<# Author: Nicklas Eriksson
 Date: 2021-03-11
 Purpose: Download HP Drivers and apply HPIA drivers during OS Deployment.

 Version: 1.0
 Changelog: 1.0 - 2021-02-11 - Nicklas Eriksson -  Script was created. Purpose to use one script to download and clean-up everything.

 TO-Do
 - N/A
#>

# Should be converted to ConfigMgr Adminservice. 
$URI = "https://lksrvsccm03.res.ludvika.intra/ConfigMgrWebService/ConfigMgr.asmx"
$SecretKey = "686c6eac-7e15-4ae6-bea3-2c4a31a1d44f"


$LogFile = "C:\Windows\Temp"
$HPIALogFile = "C:\Windows\Temp\HPIA"
$BIOSPwdFile  = "BIOSPwd.bin"

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
    }
    # Get Current OS version installed. 




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
    Log -Message "Setting OSDDownloadDownloadPackages: $PackageID" -type 1 -LogFile $LogFile



    # Download Drivers
    OSDDownloadContent.exe



    # apply drivers
    HPImageAssistant.exe /Operation:Analyze /Action:install /Selection:All /OfflineMode:Repository /noninteractive /Debug  /SoftpaqDownloadFolder:C:\HPIA /ReportFolder:$HPIALogFile /BIOSPwdFile:$BIOSPwdFile
