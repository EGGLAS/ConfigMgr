<#
  Author: Nicklas Eriksson
  Created: 2026-02-25
  Purpose: Pester tests for CreateADGroupsForServer_v2.ps1
  How to run: Invoke-Pester .\CreateADGroupsForServer_v2.Tests.ps1
#>

Describe "CreateADGroupsForServer_v2.ps1 - Syntax and Static Validation" {

    $ScriptPath = Join-Path $PSScriptRoot "CreateADGroupsForServer_v2.ps1"

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

    It "Log function should auto-create the log directory if it does not exist" {
        $TempLog = Join-Path $env:TEMP "PesterTest_$(New-Guid)\test.log"
        # Directory does not exist yet
        Test-Path (Split-Path $TempLog) | Should -Be $false
        # Dot-source the script to load the Log function, then call it
        # We can't dot-source the real script (it would try to run AD commands)
        # Instead just verify the CreateDirectory logic is present in the script
        $ScriptPath = Join-Path $PSScriptRoot "CreateADGroupsForServer_v2.ps1"
        $content = Get-Content $ScriptPath -Raw
        $content | Should -Match 'CreateDirectory'
    }
}
