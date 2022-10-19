<# 
 Author: Nicklas Eriksson
 Created: 2022-04-11
 Purpose: Create AD-groups based on computer that contians in an certian OU. This AD-group can you use to delagate local admin permissions. 

 Current version: 1.0
 Changelog: 1.0 - 2022-04-11 - Nicklas Eriksson -  Script was created.

 How to run it:
 .\CreateADGroupsForServer.ps1

You running this script/function means you will not blame the author(s) if this breaks your stuff. This script/function is provided AS IS without warranty of any kind. The entire risk arising out of the use or performance of the sample scripts and documentation remains with you. 
In no event shall author(s) be held liable for any damages whatsoever (including, without limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary loss) arising out of the use of or inability to use the script or documentation. 
Simply put: Use at your own risk.

#>

$ScriptVersion = "1.0"

$LogFile = "C:\ServerAutomation\CreateADGroupsForServers.log" #Filename for the logfile.
$OUServers = "" # Specify OU path where servers exists.
$OUADGroup = "" # Specify OU path where AD-group shall be created.
$SRVPrefix = "SRV" # Getting certain computer objects that contains with a specific prefix.
$Role = "Admins" # What type of role that shall be created on the AD-groups.

$AdminGroupDescText = "Local admingroup" # AD-group desc


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


Log  -Message  "<--------------------------------------------------------------------------------------------------------------------->"  -type 1 -LogFile $LogFile
Log -Message "Script started with version: $($ScriptVersion)" -type 1 -LogFile $LogFile

# Get servers from a specific OU
try
{
    Log -Message "Getting all servers from OU path: $OUServers" -type 1 -LogFile $LogFile
    $Servers = Get-ADComputer -SearchBase $OUServers -Properties Name -Filter * | Select Name
    Log -Message " - Successfully found servers" -type 1 -LogFile $LogFile
}
catch 
{

    Log -Message " - Could not retrive servers from OU: $OUADGroup" -Type 3 -Component "Error" -LogFile $LogFile
    Log -Message " - Error code: $($_.Exception.Message)" -Type 3 -Component "Error" -LogFile $LogFile

}

# Get all AD-groups from certian path.
try
{
    Log -Message "Getting all AD-groups with following settings OU path and prefix: $OUADGroup, $SRVPrefix " -type 1 -LogFile $LogFile
    $ServersADGroup = Get-ADGroup -SearchBase $OUADGroup -Properties Name -Filter * | Where-Object Name -like "$SRVPrefix*" | Select Name
    Log -Message " - Successfully found AD-groups" -type 1 -LogFile $LogFile
}
catch 
{

    Log -Message " - Could not retrive AD-groups from OU: $OUADGroup" -Type 3 -Component "Error" -LogFile $LogFile
    Log -Message " - Error code: $($_.Exception.Message)" -Type 3 -Component "Error" -LogFile $LogFile

}
 
# Creating AD-groups.
Log -Message "Starting to create AD-groups" -type 1 -LogFile $LogFile
foreach ($Server in $Servers)
{
    
    # Create Prefix
    $AdminName = "$SRVPrefix" + "-" + "$($Server.Name)" + "-" + "$Role"
    $AdminGroupDesc = $AdminGroupDescText + " " + $Server.Name
    
    # Check if AD-group exists.
    try
    {
        
        Log -Message " - Checking if AD-group $AdminName exists" -type 1 -Component "Script" -LogFile $LogFile
        $GetADGroup = Get-ADGroup -Identity $AdminName  
    }
    catch 
    {
        Log -Message " - AD-group $AdminName does not exists" -type 1 -Component "Script" -LogFile $LogFile
        $ADgroupExist = "False" 
    }
    
    # If AD-group does not exist it will be created.
    if ($ADgroupExist -eq "False")
    {
        Log -Message "  - Creating AD-group for server: $($Server.Name)" -type 1 -LogFile $LogFile -Component "Script"

        # Create AD-group
        try
        {
            New-ADGroup -Name $AdminName -DisplayName $AdminName -Description "$AdminGroupDesc" -GroupCategory Security -GroupScope Global -Path $OUADGroup
            Log -Message "  - Successfully created AD-group: $AdminName" -type 1 -LogFile $LogFile -Component "Script"

        }
        catch
        {
            Log -Message "  - Could not create AD-group with the name: $AdminName" -Type 3 -Component "Error" -LogFile $LogFile
            Log -Message "  - Error code: $($_.Exception.Message)" -type 3 -Component "Error" -LogFile $LogFile
        }

    }
    else 
    {                
        Log -Message "  - AD-Group $AdminName exists already, skipping" -Type 1 -Component "Script" -LogFile $LogFile
    
    }      
    $ADgroupExist = "True"
}

Log -Message "Job is done, happy automation." -type 1 -LogFile $LogFile -Component "Script"
