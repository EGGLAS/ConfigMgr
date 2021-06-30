<#
.SYNOPSIS
  Download latest Surface drivers from Microsoft, get supported models from XML-file. 
  Idea came from our solution HPIA.
.DESCRIPTION

 Important links:
 https://docs.microsoft.com/en-us/surface/surface-system-sku-reference
.PARAMETER <Parameter_Name>
    .\ImportMicrosoft
.INPUTS
  <Inputs if any, otherwise state None>
.OUTPUTS
  \ImportMicrosoft.log
.NOTES
  Version:        1.0
  Author:         Nicklas Eriksson / Daniel Gråhns
  Creation Date:  2021-06-23
  Purpose/Change: Initial script development
  
.EXAMPLE
  .\ImportMicrosoft.ps1 -config .\Config.xml

.Credits
Big shoutout and credit to Maurice Dualy and Nikolaj Andersen for their outstanding work with  Modern Driver Management for making this solution possible. 
Some code are borrowed from their awesome solution to making this solution work.

#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage='Path to XML Configuration File')]
    [string]$Config
)


$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

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
<#
Type: 1 = Normal, 2 = Warning (yellow), 3 = Error (red)
#>
    $Time = Get-Date -Format "HH:mm:ss.ffffff"
    $Date = Get-Date -Format "MM-dd-yyyy"
    if ($ErrorMessage -ne $null) {$Type = 3}
    if ($Component -eq $null) {$Component = " "}
    if ($Type -eq $null) {$Type = 1}
    $LogMessage = "<![LOG[$Message $ErrorMessage" + "]LOG]!><time=`"$Time`" date=`"$Date`" component=`"$Component`" context=`"`" type=`"$Type`" thread=`"`" file=`"`">"
    $LogMessage | Out-File -Append -Encoding UTF8 -FilePath $LogFile
}


if (Test-Path -Path $Config) {
 
    $Xml = [xml](Get-Content -Path $Config -Encoding UTF8)
    Write-Host "Info: Successfully loaded $Config" -LogFile $Logfile -Type 1 -ErrorAction Ignore

 }
 else {
    
    $ErrorMessage = $_.Exception.Message
    Write-host "Info: Error, could not read $Config"  -LogFile $Logfile -Type 3 -ErrorAction Ignore
    Write-host "Info: Error message: $ErrorMessage" -LogFile $Logfile -Type 3 -ErrorAction Ignore
    Exit 1

 }
 

# Getting information from Config File
$InstallPath = $Xml.Configuration.Install | Where-Object {$_.Name -like 'InstallPath'} | Select-Object -ExpandProperty "Value"
$XMLInstallHPIA = $Xml.Configuration.Install | Where-Object {$_.Name -like 'InstallHPIA'} | Select-Object 'Enabled','Value'
$SiteCode = $Xml.Configuration.Install | Where-Object {$_.Name -like 'SiteCode'} | Select-Object -ExpandProperty 'Value'
$CMFolderPath = $Xml.Configuration.Install | Where-Object {$_.Name -like 'CMFolderPath'} | Select-Object -ExpandProperty 'Value'
$ConfigMgrModule = $Xml.Configuration.Install | Where-Object {$_.Name -like 'ConfigMgrModule'} | Select-Object -ExpandProperty 'Value'
$DriverImport = $Xml.Configuration.Install | Where-Object {$_.Name -like 'DriverImport'} | Select-Object -ExpandProperty 'Value'
$SourcePath = $Xml.Configuration.Install | Where-Object {$_.Name -like 'SourcePath'} | Select-Object -ExpandProperty 'Value'
$ModelsCSV = $Xml.Configuration.Install | Where-Object {$_.Name -like 'SupportComputerModels'} | Select-Object -ExpandProperty 'Value'
$DPGroupName = $Xml.Configuration.Install | Where-Object {$_.Name -like 'DPGroupName'} | Select-Object -ExpandProperty 'Value'
$Cleanup = $Xml.Configuration.Install | Where-Object {$_.Name -like 'Cleanup'} | Select-Object -ExpandProperty 'DriverImport'


# Hardcoded variabels in the script.
$ScriptVersion = "1.0"
$Manufacturer = "Microsoft"
$SupportedModelsCSV = $InstallPath + "\" + $ModelsCSV
$Downloadlink = $InstallPath + "\" + "DownloadLinks.csv"
$LogFile = "$InstallPath\MicrosoftUpdate.log" #Filename for the logfile.
[int]$MaxLogSize = 9999999
$OldOSVersions = @('18362','18363','19041')


#If the log file exists and is larger then the maximum then roll it over with with an move function, the old log file name will be .lo_ after.
If (Test-path  $LogFile -PathType Leaf) {
    If ((Get-Item $LogFile).length -gt $MaxLogSize){
        Move-Item -Force $LogFile ($LogFile -replace ".$","_")
        Log -Message "The old log file it's to big renaming it, creating a new logfile" -LogFile $Logfile

    }
}

# Create download folder
if (!(Test-path -Path "$InstallPath\Download"))
{
    Write-host "Creating download folder"
    New-item -ItemType Directory -Path $InstallPath -Name "Download"
}
else {
    Write-host "Download folder exits, no need to create it again." 
}

#Importing download links from CSV file
if (Test-path $Downloadlink) {
	$DownloadLinktoImport = Import-Csv -Path $Downloadlink -ErrorAction Stop

        Log -Message "Info: $($DownloadLinktoImport.Downloadlink.Count) download links found" -Type 1 -LogFile $LogFile -Component FileImport
        Write-host "Info: $($DownloadLinktoImport.Downloadlink.Count) download links found" 
}
else {
    Write-host "Could not find any DownloadLinks.csv file, the script will break" -ForegroundColor Red
    Log -Message "Could not find any $($Downloadlink) file, the script will break" -Type 3 -LogFile $LogFile -Component FileImport
    Break
}

#Importing supported computer models CSV file
if (Test-path $SupportedModelsCSV) {
	$ModelsToImport = Import-Csv -Path $SupportedModelsCSV -ErrorAction Stop
    if ($ModelsToImport.Model.Count -gt "1")
    {
        Log -Message "Info: $($ModelsToImport.Model.Count) models found" -Type 1 -LogFile $LogFile -Component FileImport
        Write-host "Info: $($ModelsToImport.Model.Count) models found"

    }
    else
    {
        Log -Message "Info: $($ModelsToImport.Model.Count) model found" -Type 1 -LogFile $LogFile -Component FileImport
        Write-host "Info: $($ModelsToImport.Model.Count) model found"

    }   
}
else {
    Write-host "Could not find any .CSV file, the script will break" -ForegroundColor Red
    Log -Message "Could not find any .CSV file, the script will break" -Type 3 -LogFile $LogFile -Component FileImport
    Break
}

# Creating table for all computer models.
$AllMicrosoftsModels = foreach ($Model in $ModelsToImport) {
    @(
    @{ SystemSKU = "$($Model.SystemSKU)"; Model = "$($Model.Model)"; OSVER = $Model.WindowsVersion }
    )
    Log -Message "Added $($Model.SystemSKU), $($Model.Model), $($Model.OSVER) to download list" -type 1 -LogFile $LogFile -Component FileImport
    Write-host "Info: Added $($Model.SystemSKU), $($Model.Model), $($Model.OSVER) to download list" 
}

# Creating download table from CSV File
$AllMicrosoftsDownloadModels = foreach ($Download in $DownloadLinktoImport) {
    @(
    @{ SystemSKU = "$($Download.SystemSku)"; DownloadLink = "$($Download.Downloadlink)" }
    )
    Log -Message "Added $($Download.Downloadlink) to download list" -type 1 -LogFile $LogFile -Component FileImport
    Write-host "Info: Added $($Download.Downloadlink) to download list" 
}

# ConfigMgr part start here    
Import-Module $ConfigMgrModule
if ((Test-path $CMfolderPath) -eq $false)
{
    Log -Message "$CMFolderPath does not exists in ConfigMgr, creating folder path" -type 2 -LogFile $LogFile -Component ConfigMgr
    Set-location "$($SiteCode):\"
    New-Item -ItemType directory -Path $CMfolderPath
    Log -Message "$CMFolderPath was successfully created in ConfigMgr" -type 2 -LogFile $LogFile -Component ConfigMgr
    Set-Location -Path "$($InstallPath)"
}


foreach ($Model in $AllMicrosoftsModels)
{
    Write-host "Info: Starting the process for Computermodel: $($Model.Model)"
    Log -Message "Info: Starting the process for Computermodel: $($Model.Model)" -type 1 -LogFile $LogFile -Component Microsoft

    Write-Host "Info: Will download drivers for OSVersion: $($Model.OSVER), need to transalte $($Model.OSVER) to OS Buildnumber"
    Log -Message "Info: Starting the process for Computermodel: $($Model.Model)" -type 1 -LogFile $LogFile -Component OSVER

    switch ($Model.OSVER)
    {
        "20H2" {
               $OSVersion = "19042"
                
        }
        "21H2" {
               $OSVersion = "19043"
        }
    }
    Write-Host "Info: Translated OSVer $($Model.OSVer) to OS Buildnumer $($OSVersion)"
    Log -Message "Info: Translated OSVer $($Model.OSVer) to OS Buildnumer $($OSVersion)" -type 1 -LogFile $LogFile -Component OSVER

    $SystemSKU = $($model.SystemSKU)
    $TrimModel = $($Model).Model.replace(' ','')
    # Create download link 
    Write-host "Info: Attempting to create download link for $TrimModel)"
    Log -Message "Info: Attempting to create download link for $TrimModel" -type 1 -LogFile $LogFile -Component Webrequest
    
    $CreatedDownloadLink = $AllMicrosoftsDownloadModels | Where-Object SystemSKU -eq "$SystemSKU"
    Write "Info: $($CreatedDownloadLink.DownloadLink)"
    $MSDownloadLink = "$($CreatedDownloadLink.DownloadLink)$OSVersion"
    write-host "Info: Download link is created: $($MSDownloadLink)"
    Log -Message "Info: Download link is created: $($MSDownloadLink)" -type 1 -LogFile $LogFile -Component Webrequest

    $Request = [System.Net.WebRequest]::Create($MSDownloadLink)
	$Request.AllowAutoRedirect = $false
	$Request.Timeout = 9000
	$Response = $Request.GetResponse()
	if ($Response.ResponseUri) {
			[string]$ReturnedURL = $Response.GetResponseHeader("Location")
            Write-host "Info: Starting check to see if link is good or not $([string]$ReturnedURL)"
            if ($ReturnedURL -match ".msi")
            {
                Write-host "Info: Link is good will contiune with downloading the MSI for $TrimModel"
            }
            else
            {
                Write-host "Info: Bad link, no MSI is found on this link. Trying older Windows 10 build numbers to download drivers for $TrimModel." -ForegroundColor Red               
                Log -Message "Bad link, no MSI is found on this link. Trying older Windows 10 build numbers to download drivers for $TrimModel" -type 3 -LogFile $LogFile -Component Webrequest

                foreach ($OldOSVer in $OldOSVersions)
                {

                           $MSDownloadLink = "$($CreatedDownloadLink.DownloadLink)$OldOSVer"
                           write-host "Info: Download link is created: $($MSDownloadLink)"
                           Log -Message "Download link is created: $($MSDownloadLink)" -type 1 -LogFile $LogFile -Component Webrequest


                            $Request = [System.Net.WebRequest]::Create($MSDownloadLink)
	                        $Request.AllowAutoRedirect = $false
	                        $Request.Timeout = 9000
	                        $Response = $Request.GetResponse()
	                        if ($Response.ResponseUri) {
			                [string]$ReturnedURL = $Response.GetResponseHeader("Location")

                            # Check if URL contains .MSI if MSI are found it will return the value for download.                            
                            if ([string]$ReturnedURL -match ".msi")
                            {
                                write-host "Info: MSI Found with OS Buildnumber $OldOSVer for $TrimModel, will contiune the process for downloading drivers now."
                                Log -Message "MSI Found with OS Buildnumber $OldOSVer for $TrimModel, will contiune the process for downloading drivers now." -type 1 -LogFile $LogFile -Component Webrequest

                                Break
                            }
                            
                }

            } 
                
        }
    }
    $Response.Close()    
       
        # Download MSI Package from Microsoft.
        try
        {
            
            # Trimming Model name to get MSI Name.
            #$ReturnedURL
            $DownloadPath = $InstallPath + "\Download"
            $MSIBaseName = "$ReturnedURL"
            $MSIVersion = $MSIBaseName.substring($MSIBaseName.length - 18, 18)
            $Fullversion = ($MSIVersion).Replace(".msi","")

            $ModelSourcePath = $SourcePath + "\" + $Manufacturer + "\" + $Model.OSVER + "\" + $Model.Model + "\" + $Fullversion     

            #$CharArray =$Fullversion.Split(".")
            #$CharArray[0,1]

            if (!(Test-path $ModelSourcePath))
            {
                Write-host "Info: Starting to download MSI for $($Model.model) from $($ReturnedURL)"
                Log -Message "Info: Starting to download MSI for $($Model.model) from $($ReturnedURL)" -type 1 -LogFile $LogFile -Component ConfigMgr

                Start-BitsTransfer -Source $ReturnedURL -Destination "$DownloadPath" -TransferType Download -Priority Foreground
                Write-host "Info: Download is completed."
                Log -Message "Info: Download is completed. $($MSDownloadLink)" -type 1 -LogFile $LogFile -Component ConfigMgr

            }
            else
            {
                Write-host "Info: No need to download MSI again because it's already exits in $ModelSourcePath"
                Log -Message "Info: No need to download MSI again because it's already exits in $ModelSourcePath" -type 1 -LogFile $LogFile -Component ConfigMgr

            }
        }
        catch 
        {
            Write-Host "Info: Could not download from $ReturnedURL" -ForegroundColor Red
            Log -Message "Info: Could not download from $ReturnedURL" -type 3 -LogFile $LogFile -Component ConfigMgr

            throw
        }
        
		
    # Creating Source Path, remanining to create some kind of version id. Use the same solution for DriverImport IMO. 
    # Then create an match earlier in the script to see if the model exits or not.
    if (!(Test-Path $ModelSourcePath))
    {
        Write-host "Info: Creating $ModelSourcePath"
        Log -Message "Info: Creating $ModelSourcePath" -type 1 -LogFile $LogFile -Component ConfigMgr

        New-Item -ItemType Directory -Path $ModelSourcePath -ErrorAction Stop
        Write-host "Info: DriverSource Path is created: $ModelSourcePath"
        Log -Message "Info: DriverSource Path is created: $ModelSourcePath" -type 1 -LogFile $LogFile -Component ConfigMgr

        try
        {
            # Get MSI
            $MSIName = Get-ChildItem -Path $DownloadPath -Filter "*.MSI" | select Name, BaseName, Path -Last 1
            $DriverImportPath = $DriverImport + "\" + $Manufacturer + "\" + $Model.OSVER + "\" + $Model.Model + "\" + $Fullversion    
            # Creating DriverImport 
            if (!(Test-path $DriverImportPath)) 
            {
                Write-host "Info: Creating $DriverImportPath"
                Log -Message "Info: DriverSource Path is created: $ModelSourcePath" -type 1 -LogFile $LogFile -Component ConfigMgr

                New-Item -ItemType Directory -Path $DriverImportPath -ErrorAction Stop
                Write-host "Info: $DriverImportPath is created." 
                Log -Message "Info: DriverSource Path is created: $ModelSourcePath" -type 1 -LogFile $LogFile -Component ConfigMgr

            }
            else
            {
                Write-host "Info: No need to create $DriverImportPath"
            }


            # Unpacking MSI with /A to specificed location.
            Write-host "Info: Starting to unpack $($MSIName.Name) to $DriverImportPath"
            Log -Message "Info: Starting to unpack $($MSIName.Name) to $DriverImportPath" -type 1 -LogFile $LogFile -Component ConfigMgr
            $MSISilentSwitches = "/a" + '"' + $("$InstallPath\Download\") + $MSIName.Name + '"' + '/QN TARGETDIR="' + $DriverImportPath + '"'
		    $MSIProcess = Start-Process msiexec.exe -ArgumentList $MSISilentSwitches -PassThru
	        # Wait for Microsoft Driver Process To Finish
	        While ((Get-Process).ID -eq $MSIProcess.ID) {
		    Start-Sleep -seconds 30
            write-host "Info: MSI process are still runing with processID $($MSIProcess.ID) "
            Log -Message "Info: MSI process are still runing with processID $($MSIProcess.ID)" -type 1 -LogFile $LogFile -Component ConfigMgr

            }
            Write-host "Info: Unpacking MSI is now done, files are located at $DriverImportPath"
            Write-host "Info: Continue with the next step"
            Log -Message "Info: Unpacking MSI is now done, files are located at $DriverImportPath" -type 1 -LogFile $LogFile -Component ConfigMgr
            Log -Message "Info: Continue with the next step" -type 1 -LogFile $LogFile -Component ConfigMgr
    
            # Zipping drivers
            Write-host "Info: Starting to compress drivers to ZIP format."
            Write-host "Info: ZIP file will be found at $ModelSourcePath"
            Log -Message "Info: Starting to compress drivers to ZIP format." -type 1 -LogFile $LogFile -Component ConfigMgr
            Log -Message "Info: ZIP file will be found at $ModelSourcePath" -type 1 -LogFile $LogFile -Component ConfigMgr
 
            Compress-Archive -Path $DriverImportPath -DestinationPath "$ModelSourcePath\$($Model.Model)" -CompressionLevel Optimal
            Write-host "Info: Compressing drivers to ZIP is now done."
            Log -Message "Info: Compressing drivers to ZIP is now done" -type 1 -LogFile $LogFile -Component ConfigMgr


            # Cleaning up Driver Import Files.
            if ($Cleanup -eq "True")
            {
                Write-host "Info: Cleaning up Driver Import Files"
                Log -Message "Info: Cleaning up Driver Import Files" -type 1 -LogFile $LogFile -Component ConfigMgr

                Remove-item -path $DriverImportPath -force -Recurse -ErrorAction Ignore 
            }
            else
            {
                Log -Message "Info: Cleaning up files were not selected in the config" -type 1 -LogFile $LogFile -Component ConfigMgr
                Write-host "Info: Cleaning up files were not selected in the config"
            } 

        }
        catch 
        {
            Write-Host "Info: Could not unpack $($MSIName.Name) from $($MSIName.Path)"
            Log -Message "Info: Could not unpack $($MSIName.Name) from $($MSIName.Path)" -type 1 -LogFile $LogFile -Component ConfigMgr
            throw

        }
 
    }
    else
    {
        Write-host "Info: No need to create $ModelSourcePath because it's already exists"
        Log -Message "Info: No need to create $ModelSourcePath because it's already exists" -type 1 -LogFile $LogFile -Component ConfigMgr

    }
    
        
###########
# ConfigMgr part start here now.
###########


    Set-location "$($SiteCode):\"
    $SourcesLocation = $ModelSourcePath # Set Source location
    $PackageManufacturer = "$Manufacturer" # hardcoded variable, will be used inside the ApplyHPIA.ps1 script, Please dont change this.
    $PackageVersion = "$Fullversion"
    $PackageName = "$Manufacturer - $($Model.OSVER) -" + " $($Model.Model) -" + " $($Model.SystemSKU)" #Must be below 40 characters, hardcoded variable, will be used inside the ApplyHPIA.ps1 script, Please dont change this.
    $PackageDescription = "$OSVER-" + "$($Model.Model)" + " $($Model.SystemSKU)"
    $SilentInstallCommand = ""
    
    # Check if package exists in ConfigMgr, if not it will be created.
    $PackageExist = Get-CMPackage -Fast -Name $PackageName
    If ([string]::IsNullOrWhiteSpace($PackageExist)){
        #Write-Host "Does not Exist"
        Log -Message "$PackageName does not exists in ConfigMgr" -type 1 -LogFile $LogFile -Component ConfigMgr
        Log -Message "Creating $PackageName in ConfigMgr" -type 1 -LogFile $LogFile -Component ConfigMgr
        Write-host "Info: $PackageName does not exists in ConfigMgr"
        Write-host "Info: Creating $PackageName in ConfigMgr"
        New-CMPackage -Name $PackageName -Description $PackageDescription -Manufacturer $PackageManufacturer -Version $PackageVersion -Path $SourcesLocation
        Set-CMPackage -Name $PackageName -DistributionPriority Normal -CopyToPackageShareOnDistributionPoints $True -EnableBinaryDeltaReplication $True
        Log -Message "$PackageName is created in ConfigMgr" -LogFile $LogFile -Type 1 -Component ConfigMgr    
        Start-CMContentDistribution -PackageName  "$PackageName" -DistributionPointGroupName "$DPGroupName" 
        Log -Message "Starting to send out $PackageName to $DPGroupName" -type 1 -LogFile $LogFile -Component ConfigMgr
        $MovePackage = Get-CMPackage -Fast -Name $PackageName        
        Move-CMObject -FolderPath $CMFolderPath -InputObject $MovePackage
        Log -Message "Moving ConfigMgr package to $CMFolderPath" -LogFile $LogFile -Component ConfigMgr -Type 1
        
        Set-Location -Path "$($InstallPath)"
        Write-host "Info: $PackageName is created in ConfigMgr and distributed to $DPGroupName"
        Write-host "Info: $($Model.Model) is done, continue with next model in the list."
        Log -Message "$($Model.Model) is done, continue with next model in the list." -type 1 -LogFile $LogFile

    }
    Else {

            Set-Location -Path $($InstallPath)
            Write-host "Info: Latest version for $($Model.Model) already exists in ConfigMgr, continue with next model in the list."  -ForegroundColor Green
            Log -Message "$($Model.Model) is done, continue with next model in the list." -type 1 -LogFile $LogFile
    }

    
   
       
}


# Setting location back to where it should be.
Set-Location -Path "$($InstallPath)"

# Clean-up files as the last step before contiune with the next model if's sets in config.xml file..
Write-host "Info: Cleaning up...."
Log -Message "Info: Cleaning up...." -type 1 -LogFile $LogFile -Component ConfigMgr

# Only deleteing .MSI files if there are any found in the download path.
$MSITempDownloaded = Get-ChildItem -Path $DownloadPath | select FullName
if ($MSITempDownloaded.FullName -match ".msi")
{
foreach ($TempDownloaded in $MSITempDownloaded.FullName)
    {
    Write-host "Info: Deleting $TempDownloaded"
    Log -Message "Info: Deleting $TempDownloaded." -type 1 -LogFile $LogFile -Component ConfigMgr
    Remove-Item -Path $TempDownloaded  -Recurse -Verbose
    }

}
else
{
    Write-host "Info: Nothing found to cleanup."
}

$stopwatch.Stop()
$FinalTime = $stopwatch.Elapsed
Write-host "Info: Runtime: $FinalTime"
Write-host "Info: Microsoft Update Complete" -ForegroundColor Green
Log -Message "Runtime: $FinalTime" -LogFile $Logfile -Type 1 -Component Microsoft
Log -Message "Microsoft Update Complete" -LogFile $LogFile -Type 1 -Component Microsoft
Log -Message "----------------------------------------------------------------------------" -LogFile $LogFile