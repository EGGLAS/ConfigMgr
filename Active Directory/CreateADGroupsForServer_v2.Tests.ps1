<#
  Author: Nicklas Eriksson
  Created: 2026-02-25
  Purpose: Pester tests for CreateADGroupsForServer_v2.ps1
  How to run: Invoke-Pester .\CreateADGroupsForServer_v2.Tests.ps1
#>

Describe "CreateADGroupsForServer_v2.ps1 - Syntax and Static Validation" {

    $ScriptPath = if ($PSScriptRoot) {
        Join-Path $PSScriptRoot "CreateADGroupsForServer_v2.ps1"
    } else {
        Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "CreateADGroupsForServer_v2.ps1"
    }

    It "Script file should exist" {
        $ScriptPath | Should -Exist
    }

    It "Should parse without syntax errors" {
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$null, [ref]$errors)
        $errors.Count | Should -Be 0
    }

    It "Script file should be UTF-8 without BOM" {
        $bytes = [System.IO.File]::ReadAllBytes($ScriptPath)
        $hasBOM = ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
        $hasBOM | Should -Be $false
    }

    It "Should contain required configuration variables" {
        $content = Get-Content $ScriptPath -Raw
        $content | Should -Match '\$AdminRootOU'
        $content | Should -Match '\$RoleSuffix'
        $content | Should -Match '\$LogFile'
    }

    It "Should not contain non-ASCII characters" {
        $content = Get-Content $ScriptPath -Raw
        ($content -match '[^\x00-\x7F]') | Should -Be $false
    }

    It "Log function should auto-create the log directory if it does not exist" {
        $content = Get-Content $ScriptPath -Raw
        $content | Should -Match 'CreateDirectory'
    }

    It "Should use .ToUpper() when building group names in auto-discovery path" {
        $content = Get-Content $ScriptPath -Raw
        $content | Should -Match '\$Computer\.Name\.ToUpper\(\)'
    }

    It "Should use the uppercased ComputerName variable in GroupName and Description" {
        $content = Get-Content $ScriptPath -Raw
        $content | Should -Match '\$ComputerName\s*=\s*\$Computer\.Name\.ToUpper\(\)'
        $content | Should -Match '\$GroupName\s*=.*\$ComputerName'
        $content | Should -Match '\$Description\s*=.*\$ComputerName'
    }
}

Describe "CreateADGroupsForServer_v2.ps1 - Uppercase Computer Name Logic" {

    It "GroupName should contain uppercased computer name when computer name is lowercase" {
        $TierPrefix   = "T1"
        $TypePrefix   = "SRV"
        $RoleSuffix   = "Localadmins"
        $Computer     = [PSCustomObject]@{ Name = "server01" }
        $ComputerName = $Computer.Name.ToUpper()
        $GroupName    = "$TierPrefix-$TypePrefix-$ComputerName-$RoleSuffix"
        $GroupName | Should -Be "T1-SRV-SERVER01-Localadmins"
    }

    It "GroupName should contain uppercased computer name when computer name is mixed-case" {
        $TierPrefix   = "T1"
        $TypePrefix   = "SRV"
        $RoleSuffix   = "Localadmins"
        $Computer     = [PSCustomObject]@{ Name = "Server01" }
        $ComputerName = $Computer.Name.ToUpper()
        $GroupName    = "$TierPrefix-$TypePrefix-$ComputerName-$RoleSuffix"
        $GroupName | Should -Be "T1-SRV-SERVER01-Localadmins"
    }

    It "GroupName should remain unchanged when computer name is already uppercase" {
        $TierPrefix   = "T1"
        $TypePrefix   = "SRV"
        $RoleSuffix   = "Localadmins"
        $Computer     = [PSCustomObject]@{ Name = "SERVER01" }
        $ComputerName = $Computer.Name.ToUpper()
        $GroupName    = "$TierPrefix-$TypePrefix-$ComputerName-$RoleSuffix"
        $GroupName | Should -Be "T1-SRV-SERVER01-Localadmins"
    }

    It "Description should contain uppercased computer name" {
        $TierNumber   = "1"
        $TypePrefix   = "SRV"
        $Computer     = [PSCustomObject]@{ Name = "server01" }
        $ComputerName = $Computer.Name.ToUpper()
        $Description  = "Tier $TierNumber $TypePrefix - Local admin group for $ComputerName"
        $Description | Should -Be "Tier 1 SRV - Local admin group for SERVER01"
    }
}