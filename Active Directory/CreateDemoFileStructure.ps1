<#
.SYNOPSIS
This PowerShell script creates a demo file structure under C:\Shares\Demo and adds Active Directory users and groups with random permissions.

.DESCRIPTION
This script automates the following tasks:
1. Creates a root directory at C:\Shares\Demo if it doesn't already exist.
2. Creates 10 Active Directory user accounts with the naming convention useraccount1 to useraccount10.
3. Creates 10 Active Directory groups with the naming convention Usergroups1 to Usergroups10.
4. Generates random permissions for directories and assigns them to user accounts and groups.
5. Modifies permissions to allow file creation in directories.
6. Creates various types of files (e.g., .txt, .docx, .xlsx, .pptx, .jpg, .png, .pdf) within each directory.

How to delete files when your lab is done: 
1. Run CMD with admin rights.
2. takeown /F * /R /D Y
3. icacls . /T /C /grant administrators:F System:F everyone:F
4. del * /s /q

.NOTES
File Name      : CreateDemoFileStructure.ps1
Prerequisite   : Active Directory module
Author         : Nicklas Eriksson
Copyright 2023 : Labb
#>

param (
    [Parameter(
    HelpMessage = "Specifies the path to the root folder of the file share to be reviewed.", 
    Mandatory= $true
    )]
    $RootDirectory = ""
)



# Import the Active Directory module
Import-Module ActiveDirectory

# Variables
$Username = "useraccount$i" # AD-User Name, kepp $i in the variable.
$Password = "P@ssw0rd"  # You should set a secure password here
$ADGroupPath = "OU=Groups,OU=EGGLAS,DC=Test,DC=local" # Enter path where the AD-groups should be created.
$ADUserPath = "OU=Users,OU=EGGLAS,DC=Test,DC=local" # Enter path where the AD-users should be created.
$Domain = "Egglas.local" # Domain name
$MaxUseraccounts = 15  # Specify how many user accounts you wish to create.
$MaxGroupAccount = 15 # Specifiy how man groups you wish to create.
$MaxFolders = 10 # Adjust the number of folders you wish to create. 
$MaxFilesPerFolder = 5  # Adjust the number of files per folder as needed.
$FileExtensions = @(".txt", ".docx", ".xlsx", ".pptx", ".jpg", ".png", ".pdf") # Different file extensions


# Check if the root directory already exists
if (Test-Path -Path $RootDirectory -PathType Container) {
    $Continue = Read-Host "The root directory '$RootDirectory' already exists. Do you want to continue? (Y/N)"
    if ($Continue -ne "Y" -and $Continue -ne "y") {
        Write-Host "Script execution cancelled by the user." -ForegroundColor Green
        Break
    }
    else {
        Write-host "User pressed Yes, script will continue" -ForegroundColor Cyan
    }
}

# Create the root directory if it doesn't exist
if (-not (Test-Path -Path $RootDirectory -PathType Container)) {
    New-Item -Path $RootDirectory -ItemType Directory
}


# Function to create or get an AD user account
function Create-ADUserIfNeeded($Username, $Password) {
    $ExistingUser = Get-ADUser -Filter { SamAccountName -eq $Username }
    
    if ($ExistingUser) {
        Write-Host "User account '$Username' already exists. Skipping creation." -ForegroundColor Cyan
    }
    else {
        Write-Host "Creating user account '$Username'..." -ForegroundColor Cyan
        New-ADUser -Name $Username -SamAccountName $Username -UserPrincipalName "$Username@egglas.local" -AccountPassword (ConvertTo-SecureString -String $Password -AsPlainText -Force) -Enabled $true -Path $ADUserPath
    }
}

# Create Active Directory users named useraccount1 to useraccount10 if they don't already exist
for ($i = 1; $i -le $MaxUseraccounts; $i++) {
    #$Username = "useraccount$i"
    #$Password = "P@ssw0rd"  # You should set a secure password here

    Create-ADUserIfNeeded -Username $Username -Password $Password
}

# Function to create or get an AD group
function Create-ADGroupIfNeeded($GroupName) {
    $ExistingGroup = Get-ADGroup -Filter { Name -eq $GroupName }
    
    if ($ExistingGroup) {
        Write-Host "Group '$GroupName' already exists. Skipping creation." -ForegroundColor Cyan
    }
    else {
        Write-Host "Creating group '$GroupName'..." -ForegroundColor Cyan
        New-ADGroup -Name $GroupName -GroupScope Global -GroupCategory Security -Path $ADGroupPath
    }
}

# Create Active Directory groups named Usergroups1 to Usergroups10 if they don't already exist
for ($i = 1; $i -le $MaxGroupAccount; $i++) {
    $GroupName = "Usergroups$i"

    Create-ADGroupIfNeeded -GroupName $GroupName
}

# Function to generate random permissions for an AD user
function Get-RandomPermissionForUser($Username) {
    $AccessControlType = Get-Random -InputObject @("Allow", "Deny")
    $FileSystemRights = Get-Random -InputObject @(
        "ReadData",
        "WriteData",
        "AppendData",
        "ReadExtendedAttributes",
        "WriteExtendedAttributes",
        "Traverse",
        "ExecuteFile",
        "DeleteSubdirectoriesAndFiles",
        "ReadAttributes",
        "WriteAttributes",
        "Delete",
        "ReadPermissions",
        "ChangePermissions",
        "TakeOwnership",
        "Synchronize",
        "FullControl"
    )

    $IdentityReference = "$Domain\$Username"  # Set the appropriate domain and username format

    $InheritanceFlags = [System.Security.AccessControl.InheritanceFlags]"None"
    $PropagationFlags = [System.Security.AccessControl.PropagationFlags]"None"

    New-Object Security.AccessControl.FileSystemAccessRule(
        $IdentityReference,
        $FileSystemRights,
        $InheritanceFlags,
        $PropagationFlags,
        $AccessControlType
    )
}

# Function to generate random permissions for an AD group
function Get-RandomPermissionForGroup($GroupName) {
    $AccessControlType = Get-Random -InputObject @("Allow", "Deny")
    $FileSystemRights = Get-Random -InputObject @(
        "ReadData",
        "WriteData",
        "AppendData",
        "ReadExtendedAttributes",
        "WriteExtendedAttributes",
        "Traverse",
        "ExecuteFile",
        "DeleteSubdirectoriesAndFiles",
        "ReadAttributes",
        "WriteAttributes",
        "Delete",
        "ReadPermissions",
        "ChangePermissions",
        "TakeOwnership",
        "Synchronize",
        "FullControl"
    )

    $IdentityReference = "$Domain\$GroupName"  # Set the appropriate domain and group name format

    $InheritanceFlags = [System.Security.AccessControl.InheritanceFlags]"None"
    $PropagationFlags = [System.Security.AccessControl.PropagationFlags]"None"

    New-Object Security.AccessControl.FileSystemAccessRule(
        $IdentityReference,
        $FileSystemRights,
        $InheritanceFlags,
        $PropagationFlags,
        $AccessControlType
    )
}


# Initialize counters to track the progress
$foldersCreated = 0
$filesCreated = 0

# Create folders and files with random permissions
for ($i = 1; $i -le $MaxFolders; $i++) {
    $DirectoryName = "Folder$i"
    $DirectoryPath = Join-Path -Path $RootDirectory -ChildPath $DirectoryName

    # Create the directory
    New-Item -Path $DirectoryPath -ItemType Directory
    $foldersCreated++
    
    # Display the progress for folders
    Write-Host "Created folder $foldersCreated of $MaxFolders folders" -ForegroundColor Cyan

    # Apply random permissions to the directory for users and groups
    $ADUsernames = 1..$MaxUseraccounts | ForEach-Object { "useraccount$_" }
    $ADGroupnames = 1..$MaxGroupAccount | ForEach-Object { "Usergroups$_" }
    $ADPrincipals = $ADUsernames + $ADGroupnames
    foreach ($Principal in $ADPrincipals) {
        $DirectoryAcl = Get-Acl -Path $DirectoryPath
        $DirectoryAcl.AddAccessRule((Get-RandomPermissionForUser $Principal))
        Set-Acl -Path $DirectoryPath -AclObject $DirectoryAcl
    }

    # Create files within each folder and apply random permissions to each file for users and groups
    $FileExtensions = @(".txt", ".docx", ".xlsx", ".pptx", ".jpg", ".png", ".pdf")
    foreach ($Principal in $ADPrincipals) {
        for ($j = 1; $j -le $MaxFilesPerFolder; $j++) {
            $UniqueIdentifier = [System.Guid]::NewGuid().ToString("N")
            $FileName = "File$j$UniqueIdentifier$($FileExtensions | Get-Random)"
            $FilePath = Join-Path -Path $DirectoryPath -ChildPath $FileName

            # Create the file
            New-Item -Path $FilePath -ItemType File
            $filesCreated++
    
            # Display the progress for files
            Write-Host "Created file $filesCreated of $($MaxFilesPerFolder * $MaxFolders * ($MaxUseraccounts + $MaxGroupAccount)) files" -ForegroundColor Cyan

            # Apply random permissions to the file for users and groups
            $FileAcl = Get-Acl -Path $FilePath
            $FileAcl.AddAccessRule((Get-RandomPermissionForUser $Principal))
            Set-Acl -Path $FilePath -AclObject $FileAcl
        }
    }
}

Write-Host "Demo file structure with random permissions, Active Directory users, groups, folders, and files created successfully." -ForegroundColor Green