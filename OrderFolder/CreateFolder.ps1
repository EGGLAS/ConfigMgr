<# Author: Nicklas Eriksson
 Date: 2021-12-06
 Purpose: Create 
            - folder
            - AD-groups 
          - add members to AD-groups
          - Send Email to Owners.
 Version: 1.0
 Changelog: 1.0 - 2021-02-11 - Nicklas Eriksson -  Script was created.

What is done:
 - Create folder
 - Create AD-groups
    - Add Members to AD-group 
 - Logging
 - Set enddate on the folder and AD-groups.
 - Check if the folder already exits, script will exit if folder exists.
 - Send email to AD-group owners.
 - SQL Loggning and update DB table with correct information.
  - May need to update with more information to the table and some other improvments.

TO-Do:
 - Need to handle inheritance on the folder. 
 - How do we handle owners of the folder?
 - Need to handle if add members is empty.
 - Check regex for date and foldername.
  - -match ('[^a-zA-Z0-9._-]')
 
NordicPeak 
 - Check if folder exists before order confirmation.
 - Pass ordernumber from the portal.

How to run the script:
 CreateFolder.ps1 -FolderName "Test"  


NOTES 
 
#>


[CmdletBinding(DefaultParameterSetName = "")]
param(
    [Parameter(Mandatory=$True, HelpMessage='Enter Foldername')]
    [string]$FolderName,
    [Parameter(Mandatory=$True, HelpMessage='Enter Owner')]
    [string[]]$ADGroupMembersOwners,
    [Parameter(Mandatory=$True, HelpMessage='Enter Members with the right to change the folder')]
    [string[]]$ADGroupMembersChange,
    [Parameter(Mandatory=$True, HelpMessage='Enter Readers')]
    [string[]]$ADGroupMembersRead,
    [Parameter(Mandatory=$False, HelpMessage='Enter an end date')] # Can we use match here to only get a certian format?
    [string]$EndDate
)


# Load modules ?

# Debug
#$FolderName = "Test"
$OrderNumber = "10000"

# AD V
$Domain = "EGGLAS"
$OUPath = "OU=Groups,OU=E-Tjanster,OU=EGGLAS,DC=EGGLAS,DC=local"
$Path = "\\dc01\Folder"
$FullPath = "$Path" + "\" +"$FolderName" 
$LogFile = "C:\CreateFolder.log"

# SMTP Server
$EmailFrom = "fileorder@egglas.se"
$SmtpServer = "postman.egglas.se"

# Create AD-groups
$ADGroupOwners = "$FolderName" + " " + "O"
$ADGroupRead = "$FolderName" + " " + "R"
$ADGroupChange = "$FolderName" + " " + "C" 
$ADGroups = $ADGroupOwners, $ADGroupRead, $ADGroupChange

# SQL Server Information
$SQLserverName = "DC01"
$SQLdatabaseName = "OrderFolder"
$tableName = "dbo.OrderFolder"

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

function CheckFolderPath {

    if ((Test-Path -Path $FullPath) -eq $True)
    {
        Log -Message "$($FolderName) already exists, script will exit." -Type 3 -Component "Error" -LogFile $LogFile
        break
    }

}

Function CreateSQLEntry { 
    
    try
    {
        Log -Message " - Connecting to to SQL database on: $($SQLserverName)\$($SQLDatabase)" -Type 1 -Component "Error" -LogFile $LogFile

        $Agare = "$ADGroupMembersOwners"
        $Datum = "$EndDate"
        $OrderNumber = "$OrderNumber"
        $Connection = New-Object System.Data.SQLClient.SQLConnection
        $Connection.ConnectionString = "server='$SQLserverName';database='$SQLdatabaseName';trusted_connection=true;"
        $Connection.Open()
        Log -Message " - Connection has been established on: $($SQLserverName)\$($SQLDatabase)" -Type 1 -Component "Error" -LogFile $LogFile

        $Command = New-Object System.Data.SQLClient.SQLCommand
        $Command.Connection = $Connection

          $insertquery="
          INSERT INTO $tableName
              ([FolderName],[Agare],[Datum],[OrderNumber])
            VALUES
              ('$FolderName','$Agare','$Datum','$ordernumber')"
          $Command.CommandText = $insertquery
          $Command.ExecuteNonQuery()
  
        $Connection.Close();

    }
    catch 
    {
            Log -Message "Failed to writeback to SQL table: $($SQLServer)\$($SQLDatabase)" -Type 3 -Component "Error" -LogFile $LogFile
            Log -Message "Error code: $($_.Exception.Message)" -type 3 -Component "Script" -LogFile $LogFile        

    }


}

Function AddADGroupMember
{
    foreach ($ADGroupMember in $ADGroupMembers)
    {
        try
        {
            Add-ADGroupMember -Identity $ADGroup -Members $ADGroupMember
            Log -Message " - Added user: $ADGroupMember" -type 1 -Component "Script" -LogFile $LogFile

        }
        catch 
        {
            Log -Message "Failed to add user $($ADGroupMember) to AD-group: $($ADGroup)" -Type 3 -Component "Error" -LogFile $LogFile
            Log -Message "Error code: $($_.Exception.Message)" -type 3 -Component "Script" -LogFile $LogFile

        }

    }
    
    Log -Message "All users has been added to AD-group: $($ADGroup)" -type 1 -Component "Script" -LogFile $LogFile 

}

function SendEmail
{
    Log -Message "Starting to send out mail to AD-group members in: $($ADGroupOwners)" -type 1 -Component "ADgroup" -LogFile $LogFile
    
    Log -Message " - Getting name and mail from AD-group: $($ADGroupOwners)" -type 1 -Component "ADgroup" -LogFile $LogFile    
    $ADUserMail = Get-ADGroupMember -Identity $ADGroupOwners | Get-ADUser -Properties Name,mail | select Name, Mail
    
    # Specify a recipient email address
    $EmailToAddresses = $ADUserMail
    $EmailToAddresses 
    # Put in a subject line
    $Subject = "Ärendenummer: $($OrderNumber) - $($FolderName) har skapats och är nu tillgänglig"
    # Put the DNS name or IP address of your SMTP Server
    $Smtp = new-object Net.Mail.SmtpClient($SmtpServer)
    # This line pieces together all the info into an email and sends it
        foreach ($EmailTo in $EmailToAddresses)
        {
        try
        {
             # Add text to mail
            Log -Message " - Sending email to: $($EmailTo.Mail)" -type 1 -Component "ADgroup" -LogFile $LogFile
            $Body = "Hej $($EmailTo.Name) `nMappen $($FolderName) som beställdes är nu klar."
            write-host "$body"
            Write-Host $Subject
            $Smtp.Send($EmailFrom,$EmailTo.Mail,$Subject,$Body)
        }
        catch 
        {
            Log -Message "Failed to send email to AD-user: $($EmailTo.Name)" -Type 3 -Component "Error" -LogFile $LogFile
            Log -Message "Error code: $($_.Exception.Message)" -type 3 -Component "Script" -LogFile $LogFile        

        }

    }

    
    Log -Message "Mail has been sent out to everyone in AD-group: $($ADGroupOwners)" -type 1 -Component "ADgroup" -LogFile $LogFile

}

Log -Message "Script will run with the following settings:" -type 1 -Component "ADgroup" -LogFile $LogFile

# Check if folder already exists, script break if folder exists.
CheckFolderPath
Log -Message "OrderNumber: $OrderNumber" -type 1 -Component "ADgroup" -LogFile $LogFile
Log -Message "Foldername: $Foldername" -type 1 -Component "ADgroup" -LogFile $LogFile
Log -Message "Owners: $ADGroupMembersOwners" -type 1 -Component "ADgroup" -LogFile $LogFile
Log -Message "Members: $ADGroupMembersRead" -type 1 -Component "ADgroup" -LogFile $LogFile
Log -Message "Members: $ADGroupMembersChange" -type 1 -Component "ADgroup" -LogFile $LogFile

# Create AD-Groups
Log -Message "Starting to create AD-groups: $($ADGroups)" -type 1 -Component "Script" -LogFile $LogFile

foreach ($ADGroupName in $ADGroups)
{
    try
    {
        New-ADGroup -Path $OUPath -Name $ADGroupName -DisplayName $FolderName -Description $FolderName -GroupCategory Security -GroupScope Global -ErrorAction Stop
        Log -Message " - Created AD-Group: $($ADGroupName)" -type 1 -Component "Script" -LogFile $LogFile

    }
    catch 
    {
        Log -Message "Failed to create AD-group: $($ADGroupName)" -Type 3 -Component "Error" -LogFile $LogFile
        Log -Message "Error code: $($_.Exception.Message)" -type 3 -Component "Script" -LogFile $LogFile

        exit 1

    }

}

Log -Message "All AD-groups has been created successfully" -type 1 -Component "Script" -LogFile $LogFile


# Check if variable $enddate contains something, should be only matched to numbers.
if ($EndDate -ne "")
{    
    # Write enddate to SQL table so it can be deleted.
    
    Log -Message "Starting to update $($EndDate) in the description for the following AD-Groups: $($ADGroups)" -type 1 -Component "Script" -LogFile $LogFile

    foreach ($ADGroup in $ADGroups)
    {
        Set-ADGroup -Identity $ADGroup -Description ("$FolderName " + "(" + "$EndDate" + ")" )
        Log -Message " - Setting enddate $($EndDate) in the description for AD-Group: $($ADGroup)" -type 1 -Component "Script" -LogFile $LogFile

    }
}

foreach ($ADGroup in $ADGroups)
{
    switch ($ADGroup)
    {
    $ADGroupOwners{ 
            
            Log -Message "Starting to add users to $ADGroup" -type 1 -Component "Script" -LogFile $LogFile 
            $ADGroupMembers = $ADGroupMembersOwners # This variable are we using in the function AddADGroupMemeber
            AddADGroupMember # Start Function AddADGroupMember

        }
    $ADGroupChange {
            Log -Message "Starting to add users to $ADGroup" -type 1 -Component "Script" -LogFile $LogFile 
            $ADGroupMembers = $ADGroupMembersChange # This variable are we using in the function AddADGroupMemeber
            AddADGroupMember # Start Function AddADGroupMember

        }
    $ADGroupRead {
            Log -Message "Starting to add users to $ADGroup" -type 1 -Component "Script" -LogFile $LogFile 
            $ADGroupMembers = $ADGroupMembersRead # This variable are we using in the function AddADGroupMemeber
            AddADGroupMember # Start Function AddADGroupMember           
        }
    }
}

# Create folder 
try {
    Log -Message "Starting to create folder with foldername: $FolderName" -type 1 -Component "Script" -LogFile $LogFile

    Log -Message " - Creating folder with foldername: $FolderName" -type 1 -Component "Script" -LogFile $LogFile
    New-item -Path $FullPath -ItemType Directory -ErrorAction Stop 
    Log -Message "Successfully created folder with foldername: $FolderName" -type 1 -Component "Script" -LogFile $LogFile

    

}
catch {
    Log -Message " - Could not create folder" -type 3 -Component "Script" -LogFile $LogFile
    Log -Message " - Error code: $($_.Exception.Message)" -type 3 -Component "Script" -LogFile $LogFile

    Log -Message "Job will terminate" -type 3 -Component "Script" -LogFile $LogFile
    Exit 1
}


Log -Message "Starting to set correct permissions on the folder: $($FolderName)" -type 1 -Component "Script" -LogFile $LogFile

# Setting the right permessions depening on which AD-group it is.
# Set ACL 
$acl = Get-Acl $FullPath 

# Set Owner
$SetOwnerobject = New-Object System.Security.Principal.Ntaccount("$Domain\$ADGroupOwners")
$acl.SetOwner($SetOwnerobject) # set owner
Log -Message " - Set Owner to AD-group: $($ADGroupOwners)" -type 1 -Component "Script" -LogFile $LogFile

# Set Modifiy Acccess
#$ModifiyAccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("$Domain\$ADGroupChange","Modify","Allow")
$ModifiyAccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("$Domain\$ADGroupChange","Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
$acl.SetAccessRule($ModifiyAccessRule)
Log -Message " - Set Modifiy access to AD-group: $($ADGroupChange)" -type 1 -Component "Script" -LogFile $LogFile


# Set Read Access
$ReadAccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("$Domain\$ADGroupRead","ReadAndExecute","ContainerInherit,ObjectInherit", "None", "Allow")
$acl.SetAccessRule($ReadAccessRule)
Log -Message " - Set Read access to AD-group: $($ADGroupRead)" -type 1 -Component "Script" -LogFile $LogFile


#$acl.SetAccessRuleProtection($True,$false) # Disable inheritance


$acl | Set-Acl $FullPath
Log -Message "Done with setting the correct permissions on the $($FolderName)" -type 1 -Component "Script" -LogFile $LogFile

# Start sending out mail to AD-group owners.
SendEmail

# Create SQL Entry in database
Log -Message "Starting to write information to SQL table" -type 1 -Component "SQL" -LogFile $LogFile
CreateSQLEntry
Log -Message "Done with writing information to SQL table" -type 1 -Component "SQL" -LogFile $LogFile


Log -Message "Job is done for folder: $FolderName" -type 1 -Component "Script" -LogFile $LogFile
Log -Message "---------------------------------------------------------------------------------------------------------------------------------------------------" -type 1 -Component "ADgroup" -LogFile $LogFile
