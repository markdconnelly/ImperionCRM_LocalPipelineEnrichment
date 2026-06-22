#Requires -Modules Pester
# Tests for Invoke-ImperionVaultSync (#306): the Curated Vault LP-sync arm. This is a
# SCAFFOLD (the "Later" phase of ADR-0114 §8) — the owner-zero rclone bisync arm is run
# manually by Mark and is NOT exercised here. These tests pin the scaffold contract:
#   - the cmdlet is exported and discoverable so a future build can flesh it out in place;
#   - it is inert (throws NotImplemented) rather than half-syncing an unconfigured estate;
#   - it logs a Warn that points operators at the documented manual owner-zero arm;
#   - it never attempts a live rclone/blob/DB call (no live run leaks from a scaffold).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionVaultSync (scaffold)' {
    It 'is exported by the module so the LATER phase can build in place' {
        (Get-Command -Module ImperionPipeline -Name Invoke-ImperionVaultSync -ErrorAction SilentlyContinue) |
            Should -Not -BeNullOrEmpty
    }

    It 'supports ShouldProcess (it will be a write path once wired)' {
        $cmd = Get-Command Invoke-ImperionVaultSync
        $cmd.Parameters.ContainsKey('WhatIf') | Should -BeTrue
    }

    It 'exposes an -Owner selector for per-owner sweeps' {
        $cmd = Get-Command Invoke-ImperionVaultSync
        $cmd.Parameters.ContainsKey('Owner') | Should -BeTrue
    }

    It 'is inert: throws NotImplemented rather than running' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog {}
            { Invoke-ImperionVaultSync -Confirm:$false } | Should -Throw -ExceptionType ([System.NotImplementedException])
        }
    }

    It 'under -WhatIf reports the target and does not throw (ShouldProcess honored)' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog {}
            { Invoke-ImperionVaultSync -Owner mark -WhatIf } | Should -Not -Throw
        }
    }

    It 'logs a Warn pointing at the documented manual owner-zero arm' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog {}
            try { Invoke-ImperionVaultSync -Owner mark -Confirm:$false } catch { }
            Should -Invoke Write-ImperionLog -Times 1 -ParameterFilter {
                $Level -eq 'Warn' -and $Source -eq 'vault' -and $Message -match 'scaffold' -and $Message -match 'owner'
            }
        }
    }

    It 'attempts no live rclone / blob / DB call from the scaffold' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog {}
            Mock New-ImperionDbConnection { throw 'scaffold must not open a DB connection' }
            Mock Invoke-ImperionDbQuery { throw 'scaffold must not query the DB' }
            { Invoke-ImperionVaultSync -Confirm:$false } | Should -Throw -ExceptionType ([System.NotImplementedException])
            Should -Invoke New-ImperionDbConnection -Times 0
            Should -Invoke Invoke-ImperionDbQuery -Times 0
        }
    }
}
