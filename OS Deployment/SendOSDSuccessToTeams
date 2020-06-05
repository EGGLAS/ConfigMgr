<#	
  .NOTES
  ===========================================================================
   Name: Nicklas Eriksson, IT-center
   Purpose: Cleanup all drivers that are marked as retired in Configuration Manager and deletes sourcefiles.
   Version: 1.0 - 2020-06-03
   History: 1.0 - 2020-06-03: Script was created.
   

   .original creator: 
   	Twitter : @terencebeggs
    Blog : https://www.scconfigmgr.com	
  ===========================================================================
  .DESCRIPTION
    This script uses Microsoft Teams to notify when a OSD task sequence has failed.


#>

# Change Varibels to suit your environment
$uri = 'https://outlook.office.com/webhook/e757a656-1fb0-4ad9-b8e0-15e7695d69ac@452aa124-31b2-4f44-9f43-e2d1fd785043/IncomingWebhook/a9e306ca627e4566893b8be26c5e4ca1/1dedfcec-2a99-4c48-bd7d-5e0f2710f953'
$OSDType = "OS Deployment"


$tsenv = New-Object -ComObject Microsoft.SMS.TSEnvironment

# Get Logfile from TS variable
$TSEnv.Value("SLShare")

# Date and Time
$DateTime = Get-Date -Format g #Time

# Computer Make
$Make = (Get-WmiObject -Class Win32_BIOS).Manufacturer

# Computer Model
$Model = (Get-WmiObject -Class Win32_ComputerSystem).Model

        $Difference = ([datetime]$TSEnv.Value('SMSTS_FinishTSTime')) - ([datetime]$TSEnv.Value('SMSTS_StartTSTime')) 
        $Difference = [math]::Round($Difference.TotalMinutes)

# Get Current Task Sequence
$TaskSequence = $TSenv.Value("_SMSTSPackageName")

# Computer Name
$Name = $TSenv.Value("OSDComputerName")

# Computer Serial Number
[string]$SerialNumber = (Get-WmiObject win32_bios).SerialNumber

# IP Address of the Computer
$IPAddress = (Get-WmiObject win32_Networkadapterconfiguration | Where-Object{ $_.ipaddress -notlike $null }).IPaddress | Select-Object -First 1

# these values would be retrieved from or set by an application

$body = ConvertTo-Json -Depth 4 @{
  title    = "$Name OS Deployment Sucess"
  text	 = " "
  sections = @(
    @{
      activityTitle    = 'Task Sequence'
      activitySubtitle = "$Tasksequence"
      #activityText	 = ' '
      activityImage    = 'https://pbs.twimg.com/profile_images/628680712841924608/xIIFOxFH.png' # this value would be a path to a nice image you would like to display in notifications
    },
    @{
      title = '<h2 style=color:red;>Deployment Details'
      facts = @(
        @{
          name  = 'Name'
          value = $Name
        },
               @{
          name  = 'OSD or IPU'
          value = "$OSDType"
        },
        @{
          name  = 'Finished'
          value = "$DateTime"
        },
        @{
          name  = "TS Runtime"
          value = "$Difference"
        },
        @{
          name  = 'IP Addresss'
          value = $IPAddress
        },
        @{
          name  = 'Make'
          value = $Make
        },
        @{
          name  = 'Model'
          value = $Model
        },
        @{
          name  = 'Serial'
          value = $SerialNumber
        }
      )
    }
  )
}

Invoke-RestMethod -uri $uri -Method Post -body $body -ContentType 'application/json'