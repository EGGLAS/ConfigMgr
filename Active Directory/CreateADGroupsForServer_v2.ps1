<# 
 Author: Nicklas Eriksson
 Created: 2026-02-25
 Purpose: Automatically create tiered AD security groups for all computer objects discovered under a root Admin OU in the Haggeburger.se domain.
          Tier OUs, sub-OUs (PAW / Servers / Jumphosts) and the target Groups OU are all auto-discovered - no hardcoding of individual OUs required.

 Current version: 2.3
 Changelog: 2.0 - 2026-02-25 - Nicklas Eriksson - Script was created.
                                                    Auto-discovers Tier OUs, sub-OUs and Groups OU beneath a single root OU.
                                                    Groups are named <TierPrefix>-<TypePrefix>-<ComputerName>-<RoleSuffix>.
                                                    Fixed bug from v1: $ADgroupExist is reset before each Get-ADGroup check.
            2.1 - 2026-02-25 - Nicklas Eriksson - Updated group description format: Tier <N> <Type> - Local admin group for <ComputerName>
                                                   Removed (Auto-created) suffix from descriptions.
                                                   Added fallback OU support ($FallbackTierConfig) when auto-discovery finds no Tier OUs.
            2.2 - 2026-02-25 - Nicklas Eriksson - Fixed: Log function now auto-creates the log directory if it does not exist.
            2.3 - 2026-02-26 - Nicklas Eriksson - Fixed: Computer names in group names and descriptions are now always uppercase regardless of AD casing.

 How to run it:
 .\CreateADGroupsForServer_v2.ps1

You running this script/function means you will not blame the author(s) if this breaks your stuff. This script/function is provided AS IS without warranty of any kind. The entire risk arising out of the use or performance of the sample scripts and documentation remains with you. 
In no event shall author(s) be held liable for any damages whatsoever (including, without limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary loss) arising out of the use of or inability to use the script or documentation. 
Simply put: Use at your own risk.

#>

$ScriptVersion = "2.3"

# ---------------------------------------------------------------------------
# Configuration - only these variables need to be set by the user
# ---------------------------------------------------------------------------
$AdminRootOU = "OU=Admin,DC=Haggeburger,DC=se"   # Root OU - everything is auto-discovered from here
$RoleSuffix  = "Localadmins"                      # Suffix appended to every group name
$LogFile     = "C:\ServerAutomation\CreateADGroupsTiered.log"

# Optional manual fallback - only used if no Tier OUs are auto-discovered under $AdminRootOU
# Leave empty @() to rely purely on auto-discovery
# Example entry: @{ TierPrefix = "T1"; GroupsOU = "OU=Groups,OU=Tier 1,OU=Admin,DC=Haggeburger,DC=se"; SourceOUs = @( @{ TypePrefix = "SRV"; OU = "OU=Servers,OU=Tier 1,OU=Admin,DC=Haggeburger,DC=se" }, @{ TypePrefix = "JMP"; OU = "OU=Jumphosts,OU=Tier 1,OU=Admin,DC=Haggeburger,DC=se" } ) }
$FallbackTierConfig = @()


# ---------------------------------------------------------------------------
# Log function (CMTrace-compatible) - identical to CreateADGroupsForServer.ps1
# ---------------------------------------------------------------------------
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
    [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($LogFile)) | Out-Null
    $LogMessage | Out-File -Append -Encoding UTF8 -FilePath $LogFile
}


# ---------------------------------------------------------------------------
# Helper: map a Tier OU name to a short Tier prefix (T0, T1, T2, ...)
# ---------------------------------------------------------------------------
function Get-TierPrefix {
    param([string]$TierOUName)

    switch -Regex ($TierOUName) {
        'Tier\s*0' { return "T0" }
        'Tier\s*1' { return "T1" }
        'Tier\s*2' { return "T2" }
        default    { return $null }
    }
}


# ---------------------------------------------------------------------------
# Helper: map a sub-OU name to a short Type prefix (PAW, SRV, JMP)
# ---------------------------------------------------------------------------
function Get-TypePrefix {
    param([string]$SubOUName)

    switch -Regex ($SubOUName) {
        'PAW'      { return "PAW" }
        'Server'   { return "SRV" }
        'Jumphost' { return "JMP" }
        default    { return $null }
    }
}


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
Log -Message "<--------------------------------------------------------------------------------------------------------------------->" -Type 1 -LogFile $LogFile
Log -Message "Script started with version: $($ScriptVersion)" -Type 1 -LogFile $LogFile
Log -Message "Admin root OU: $AdminRootOU" -Type 1 -LogFile $LogFile

# Step 1 - Auto-discover all Tier OUs directly under the root Admin OU
Log -Message "Discovering Tier OUs under: $AdminRootOU" -Type 1 -LogFile $LogFile

try {
    $TierOUs = Get-ADOrganizationalUnit -SearchBase $AdminRootOU -SearchScope OneLevel -Filter * |
               Where-Object { (Get-TierPrefix -TierOUName $_.Name) -ne $null }
}
catch {
    Log -Message "Could not retrieve Tier OUs from: $AdminRootOU" -Type 3 -Component "Error" -LogFile $LogFile
    Log -Message " - Error code: $($_.Exception.Message)" -Type 3 -Component "Error" -LogFile $LogFile
    exit 1
}

if (-not $TierOUs) {
    Log -Message "WARNING: No Tier OUs were auto-discovered under $AdminRootOU. Checking for manual fallback configuration..." -Type 2 -Component "Script" -LogFile $LogFile

    if ($FallbackTierConfig -and $FallbackTierConfig.Count -gt 0) {
        Log -Message " - Fallback configuration found with $($FallbackTierConfig.Count) entry/entries. Using fallback." -Type 1 -Component "Script" -LogFile $LogFile

        foreach ($Entry in $FallbackTierConfig) {
            $TierPrefix  = $Entry.TierPrefix
            $TierNumber  = $TierPrefix.Substring(1)

            Log -Message "Processing fallback Tier entry: $TierPrefix" -Type 1 -Component "Script" -LogFile $LogFile

            foreach ($SourceOU in $Entry.SourceOUs) {
                $TypePrefix = $SourceOU.TypePrefix
                Log -Message " - Processing fallback source OU: $($SourceOU.OU) (prefix: $TypePrefix)" -Type 1 -Component "Script" -LogFile $LogFile

                $Computers = $null
                try {
                    Log -Message "   - Getting computer objects from: $($SourceOU.OU)" -Type 1 -Component "Script" -LogFile $LogFile
                    $Computers = Get-ADComputer -SearchBase $SourceOU.OU -Properties Name -Filter * | Select-Object Name
                    Log -Message "   - Successfully retrieved computer objects" -Type 1 -Component "Script" -LogFile $LogFile
                }
                catch {
                    Log -Message "   - Could not retrieve computer objects from: $($SourceOU.OU)" -Type 3 -Component "Error" -LogFile $LogFile
                    Log -Message "   - Error code: $($_.Exception.Message)" -Type 3 -Component "Error" -LogFile $LogFile
                    continue
                }

                if (-not $Computers) {
                    Log -Message "   - No computer objects found in $($SourceOU.OU) - skipping." -Type 2 -Component "Script" -LogFile $LogFile
                    continue
                }

                foreach ($Computer in $Computers) {
                    $ComputerName = $Computer.Name.ToUpper()
                    $GroupName   = "$TierPrefix-$TypePrefix-$ComputerName-$RoleSuffix"
                    $Description = "Tier $TierNumber $TypePrefix - Local admin group for $ComputerName"

                    $ADgroupExist = $true

                    try {
                        Log -Message "   - Checking if AD-group $GroupName exists" -Type 1 -Component "Script" -LogFile $LogFile
                        $null = Get-ADGroup -Identity $GroupName
                    }
                    catch {
                        Log -Message "   - AD-group $GroupName does not exist" -Type 1 -Component "Script" -LogFile $LogFile
                        $ADgroupExist = $false
                    }

                    if (-not $ADgroupExist) {
                        Log -Message "   - Creating AD-group: $GroupName" -Type 1 -Component "Script" -LogFile $LogFile

                        try {
                            New-ADGroup `
                                -Name          $GroupName `
                                -DisplayName   $GroupName `
                                -Description   $Description `
                                -GroupCategory Security `
                                -GroupScope    Global `
                                -Path          $Entry.GroupsOU
                            Log -Message "   - Successfully created AD-group: $GroupName" -Type 1 -Component "Script" -LogFile $LogFile
                        }
                        catch {
                            Log -Message "   - Could not create AD-group: $GroupName" -Type 3 -Component "Error" -LogFile $LogFile
                            Log -Message "   - Error code: $($_.Exception.Message)" -Type 3 -Component "Error" -LogFile $LogFile
                        }
                    }
                    else {
                        Log -Message "   - AD-group $GroupName already exists - skipping." -Type 1 -Component "Script" -LogFile $LogFile
                    }
                }
            }
        }
    }
    else {
        Log -Message "ERROR: No Tier OUs discovered and no fallback configuration provided. Please populate `$FallbackTierConfig at the top of the script and re-run." -Type 3 -Component "Error" -LogFile $LogFile
        exit 1
    }

    Log -Message "Job is done, happy automation." -Type 1 -Component "Script" -LogFile $LogFile
    exit 0
}

Log -Message " - Discovered $($TierOUs.Count) Tier OU(s)" -Type 1 -LogFile $LogFile

foreach ($TierOU in $TierOUs) {

    $TierPrefix = Get-TierPrefix -TierOUName $TierOU.Name
    $TierNumber = $TierPrefix.Substring(1)
    Log -Message "Processing Tier OU: $($TierOU.Name) (prefix: $TierPrefix)" -Type 1 -Component "Script" -LogFile $LogFile

    # Step 2 - Find the Groups OU within this Tier OU
    $GroupsOU = $null
    try {
        $GroupsOU = Get-ADOrganizationalUnit -SearchBase $TierOU.DistinguishedName -SearchScope OneLevel -Filter {Name -eq "Groups"} |
                    Select-Object -First 1
    }
    catch {
        Log -Message " - Could not retrieve Groups OU under $($TierOU.DistinguishedName)" -Type 3 -Component "Error" -LogFile $LogFile
        Log -Message " - Error code: $($_.Exception.Message)" -Type 3 -Component "Error" -LogFile $LogFile
    }

    if (-not $GroupsOU) {
        Log -Message " - No 'Groups' OU found under $($TierOU.Name) - skipping tier." -Type 2 -Component "Script" -LogFile $LogFile
        continue
    }

    Log -Message " - Groups target OU: $($GroupsOU.DistinguishedName)" -Type 1 -Component "Script" -LogFile $LogFile

    # Step 3 - Auto-discover sub-OUs (PAW / Servers / Jumphosts) within this Tier OU
    $SubOUs = $null
    try {
        $SubOUs = Get-ADOrganizationalUnit -SearchBase $TierOU.DistinguishedName -SearchScope OneLevel -Filter * |
                  Where-Object { (Get-TypePrefix -SubOUName $_.Name) -ne $null }
    }
    catch {
        Log -Message " - Could not retrieve sub-OUs under $($TierOU.DistinguishedName)" -Type 3 -Component "Error" -LogFile $LogFile
        Log -Message " - Error code: $($_.Exception.Message)" -Type 3 -Component "Error" -LogFile $LogFile
        continue
    }

    if (-not $SubOUs) {
        Log -Message " - No relevant sub-OUs (PAW/Servers/Jumphosts) found under $($TierOU.Name) - skipping tier." -Type 2 -Component "Script" -LogFile $LogFile
        continue
    }

    foreach ($SubOU in $SubOUs) {

        $TypePrefix = Get-TypePrefix -SubOUName $SubOU.Name
        Log -Message " - Processing sub-OU: $($SubOU.Name) (prefix: $TypePrefix)" -Type 1 -Component "Script" -LogFile $LogFile

        # Step 4 - Retrieve all computer objects from this sub-OU
        $Computers = $null
        try {
            Log -Message "   - Getting computer objects from: $($SubOU.DistinguishedName)" -Type 1 -Component "Script" -LogFile $LogFile
            $Computers = Get-ADComputer -SearchBase $SubOU.DistinguishedName -Properties Name -Filter * | Select-Object Name
            Log -Message "   - Successfully retrieved computer objects" -Type 1 -Component "Script" -LogFile $LogFile
        }
        catch {
            Log -Message "   - Could not retrieve computer objects from: $($SubOU.DistinguishedName)" -Type 3 -Component "Error" -LogFile $LogFile
            Log -Message "   - Error code: $($_.Exception.Message)" -Type 3 -Component "Error" -LogFile $LogFile
            continue
        }

        if (-not $Computers) {
            Log -Message "   - No computer objects found in $($SubOU.Name) - skipping." -Type 2 -Component "Script" -LogFile $LogFile
            continue
        }

        # Step 5 - Create a group for each computer object
        foreach ($Computer in $Computers) {

            $ComputerName = $Computer.Name.ToUpper()
            $GroupName   = "$TierPrefix-$TypePrefix-$ComputerName-$RoleSuffix"
            $Description = "Tier $TierNumber $TypePrefix - Local admin group for $ComputerName"

            # Reset existence flag before every check (fixes the bleed-through bug in v1)
            $ADgroupExist = $true

            try {
                Log -Message "   - Checking if AD-group $GroupName exists" -Type 1 -Component "Script" -LogFile $LogFile
                $null = Get-ADGroup -Identity $GroupName
            }
            catch {
                Log -Message "   - AD-group $GroupName does not exist" -Type 1 -Component "Script" -LogFile $LogFile
                $ADgroupExist = $false
            }

            if (-not $ADgroupExist) {

                Log -Message "   - Creating AD-group: $GroupName" -Type 1 -Component "Script" -LogFile $LogFile

                try {
                    New-ADGroup `
                        -Name          $GroupName `
                        -DisplayName   $GroupName `
                        -Description   $Description `
                        -GroupCategory Security `
                        -GroupScope    Global `
                        -Path          $GroupsOU.DistinguishedName
                    Log -Message "   - Successfully created AD-group: $GroupName" -Type 1 -Component "Script" -LogFile $LogFile
                }
                catch {
                    Log -Message "   - Could not create AD-group: $GroupName" -Type 3 -Component "Error" -LogFile $LogFile
                    Log -Message "   - Error code: $($_.Exception.Message)" -Type 3 -Component "Error" -LogFile $LogFile
                }

            }
            else {
                Log -Message "   - AD-group $GroupName already exists - skipping." -Type 1 -Component "Script" -LogFile $LogFile
            }
        }
    }
}

Log -Message "Job is done, happy automation." -Type 1 -Component "Script" -LogFile $LogFile
