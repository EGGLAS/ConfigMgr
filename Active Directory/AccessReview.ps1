<#
.SYNOPSIS
This script performs an access review on a file share, listing the permissions assigned to users and groups on folders and files.

.DESCRIPTION
The script recursively explores a file share directory and collects information about permissions granted to users and groups. 
It identifies whether a security identity is a user or group and checks if groups are empty or not. The results are presented in a CSV format.

.VERSION
 File Author: Nicklas Eriksson
 Date: 2023-09-04
 Version: 1.0
 Changelog: 
 1.0 - 2023-09-04 - Nicklas Eriksson - Script was created. 

.PARAMETER Path
Specifies the path to the root folder of the file share to be reviewed.

.EXAMPLE
.\AccessReview.ps1 -Path "\\dc01\Shares\"

This example reviews the permissions on the file share located at "\\dc01\Shares\" and displays the results in a table.

.INHERITED PERMISSIONS
Inherited permissions are permissions that propagate from a parent object (e.g., a folder or file) to its child objects (e.g., subfolders or files). Understanding inherited permissions is crucial for security reviews as they can introduce vulnerabilities if not managed properly. By reviewing inherited permissions, you can identify situations where users or groups have unnecessary access to files or folders, which may lead to security risks.

.PATH
The 'Path' parameter specifies the path to the root folder of the file share to be reviewed. It should be provided as a valid UNC path.

.TYPE
The 'Type' column in the report indicates whether the item being reviewed is a folder or a file. This information helps identify the object type.

.OWNER
The 'Owner' column in the report displays the owner of the item. The owner is typically the user or group with the highest level of control over the item. It's important to review ownership to ensure it aligns with security policies.

.AD GROUP OR USER
The 'AD Group or User' column displays the security identity (user or group) associated with the permissions on the item.

.IDENTITY TYPE
The 'IdentityType' column specifies whether the security identity is a user or a group. Understanding the identity type is crucial for determining who has access to the item.

.GROUP EMPTY
The 'Group Empty' column indicates whether a group associated with permissions is empty or not. Empty groups can be potential security risks, and this column helps identify them.

.EXPLICIT PERMISSIONS
The 'ExplicitPermissions' column displays the permissions explicitly assigned to the item. These are the direct permissions granted to the user or group.

.EFFECTIVE PERMISSIONS
The 'EffectivePermissions' column shows the effective permissions for the user or group on the item. Effective permissions consider both explicit permissions and inherited permissions.

.INHERITED
The 'Inherited' column indicates whether the permissions on the item are inherited from a parent object. Reviewing inherited permissions is crucial for maintaining a secure access control structure.

#>


#>

param (
    [Parameter(
    HelpMessage = "Specifies the path to the root folder of the file share to be reviewed.", 
    Mandatory= $true
    )]
    [ValidateScript({
        if (Test-Path -Path $_ -PathType Container) {
            $true
        } else {
            throw "The path '$_' does not exist or is not a valid directory."
        }
    })]    [string]
    $SharePath = ""
)


# Variabels for CSV File
$CSVPath = "$ENV:USERPROFILE\Desktop"
$CSVFile = "AccessReview$(Get-Date -Format yyyMMdd_hh_mm_ss).csv"
$CSVFullPath = $CSVPath + "\" + $CSVFile

# Check if the specified path exists
if (-not (Test-Path -Path "$SharePath")) {
    Write-Host "Error: The specified path does not exist." -ForegroundColor Red
    Break
}

# Retrieve a list of all items (folders and files) within the specified path, including subfolders.
$FolderPath = $null
try {
    # Retrieve a list of all items (folders and files) within the specified path, including subfolders.
    $FolderPath = Get-ChildItem -Path "$SharePath" -Recurse -Force
}
catch {
    Write-Host "Error: Failed to retrieve items. $_" -ForegroundColor Red
    Break
}


# Create an empty ArrayList to store the access review report.
$Report = New-Object System.Collections.ArrayList

# Define a list of system-level accounts that will be excluded from the review.
$SystemAccounts = @("NT AUTHORITY\SYSTEM", "BUILTIN\Administrators", "BUILTIN\Users", "CREATOR OWNER")

# Get the total number of items found in the specified path.
$totalItems = $FolderPath.Count

# Initialize a counter to track the number of processed items.
$itemsProcessed = 0

# Set scripts Starttime 
$startTime = Get-Date

# Display a message indicating the start of the item processing.
Write-Host "Start Processing items: $totalItems" -ForegroundColor Cyan

# Loop through each item (folder or file) found in the specified path and its subfolders.
foreach ($Folder in $FolderPath) {
    # Increment the counter for processed items.
    $itemsProcessed++
    
    # Display a message indicating the current item being processed and the total number of items.
    Write-Host "Processing item $itemsProcessed of $totalItems" -ForegroundColor Cyan

    # Calculate progress
    $progressPercent = [math]::Round(($itemsProcessed / $totalItems) * 100)
    
    # Calculate elapsed time in hours, minutes, and seconds
    $elapsedTime = (Get-Date) - $startTime
    $elapsedHours = [math]::Floor($elapsedTime.TotalHours)
    $elapsedMinutes = $elapsedTime.Minutes
    $elapsedSeconds = $elapsedTime.Seconds
    
    # Calculate estimated completion time in minutes
    if ($progressPercent -eq 0) {
        $estimatedCompletionTime = "N/A"
    }
    else {
        $estimatedCompletionTime = [math]::Round(($elapsedTime.TotalMinutes / ($progressPercent / 100)) - $elapsedTime.TotalMinutes)
    }
    
    Write-Host "Progress: $progressPercent% | Elapsed Time: $($elapsedHours):$($elapsedMinutes.ToString().PadLeft(2, '0')):$($elapsedSeconds.ToString().PadLeft(2, '0')) | Estimated Completion Time: $estimatedCompletionTime minutes remaining" 
    
    # Get the Access Control List (ACL) for the current item (folder or file).
    $Acl = $null
    try {
        $Acl = Get-Acl -Path $Folder.FullName
    }
    catch {
        Write-Host "Error: Failed to retrieve ACL for $($Folder.FullName). $_" -ForegroundColor Red
        continue  # Skip to the next item
    }
    # Loop through each access rule (permission) defined in the ACL.
    foreach ($Access in $Acl.Access) {
        # Check if the identity reference (user or group) associated with the permission is not a system account.
        if ($SystemAccounts -notcontains $Access.IdentityReference.Value) {
            # Store the identity reference value (user or group) in a variable.
            $IdentityReference = $Access.IdentityReference.Value

            # Determine the type of the identity reference (User or Group).
            $IdentityType = if ($IdentityReference -match "^[^\\]+\\(.+)$") {
                $GroupName = $Matches[1]
                if (Get-ADGroup -Filter {SamAccountName -eq $GroupName} -ErrorAction SilentlyContinue) {
                    'Group'
                } else {
                    'User'
                }
            } else {
                'User'
            }

            # Check if the identity reference is a group and if it's empty (has no members).
            $IsEmptyGroup = if ($IdentityType -eq 'Group') {
                $GroupMembers = Get-ADGroupMember -Identity $GroupName -ErrorAction SilentlyContinue
                if ($GroupMembers.Count -eq 0) {
                    'Yes'
                } else {
                    'No'
                }
            } else {
                'N/A'
            }

            # Define a hashtable containing properties for the access review report item.
            $Properties = [ordered]@{
                'Path'                = $Folder.FullName
                'Type'                = if ($Folder.PSIsContainer) { 'Folder' } else { 'File' }
                'Owner'               = (Get-Acl -Path $Folder.FullName).Owner
                'AD Group or User'    = $IdentityReference
                'IdentityType'        = $IdentityType
                'Group Empty'         = $IsEmptyGroup
                'Permissions'         = $Access.FileSystemRights
                'Inherited'           = $Access.IsInherited
            }
            
            # Create a PSObject with the defined properties and add it to the access review report.
            $ReportItem = New-Object PSObject -Property $Properties
            $Report.Add($ReportItem) | Out-Null
        }
    }
}

# Format and display the access review report in a table format.
$Report | Format-Table
try
{
    $Report | Export-Csv -Path $CSVFullPath -Encoding UTF8 -NoTypeInformation
    Write-host "Access Review completed. Check $CSVFile for the report." -ForegroundColor Green
}
catch [DivideByZeroException]
{
    Write-Host "Error: Failed to create CSV file CSVFullPath. $_" -ForegroundColor Red
    Write-host "Error: Access Review Failed. Please check error messages." -ForegroundColor Red
}
