#Requires -Modules Pester
# Hermetic tests for Get-ImperionDattoBcdrBackup: Datto BCDR request + key resolver mocked.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionDattoBcdrBackup' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'partner' } }
            Mock Resolve-ImperionDattoBcdrApiKey { 'resolved-key' }
        }
    }

    It 'flattens backup posture to the datto_bcdr_backups envelope (external_id/join = device_uid)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDattoBcdrRequest {
                , @([pscustomobject]@{
                        deviceUid       = 'DEV-1'
                        protectedStatus = 'Protected'
                        lastBackup      = '2026-06-14T03:00:00Z'
                        lastGoodBackup  = '2026-06-14T03:00:00Z'
                        backupType      = 'Agent'
                        agentVersion    = '7.0.1'
                    })
            }
            $rows = @(Get-ImperionDattoBcdrBackup)
            $rows.Count | Should -Be 1
            $rows[0].device_uid          | Should -Be 'DEV-1'
            $rows[0].protected_status    | Should -Be 'Protected'
            $rows[0].last_backup_at       | Should -Be '2026-06-14T03:00:00Z'
            $rows[0].last_good_backup_at  | Should -Be '2026-06-14T03:00:00Z'
            $rows[0].backup_type          | Should -Be 'Agent'
            $rows[0].agent_version        | Should -Be '7.0.1'
            $rows[0].source               | Should -Be 'datto_bcdr'
            $rows[0].external_id          | Should -Be 'DEV-1'
            $rows[0].content_hash         | Should -Not -BeNullOrEmpty
        }
    }

    It 'survives unknown field names: flat columns land null, raw_payload keeps everything' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDattoBcdrRequest { , @([pscustomobject]@{ deviceUid = 'DEV-9'; surpriseField = 'x' }) }
            $rows = @(Get-ImperionDattoBcdrBackup)
            $rows[0].protected_status | Should -BeNullOrEmpty
            $rows[0].external_id      | Should -Be 'DEV-9'
            $rows[0].raw_payload      | Should -Match 'surpriseField'
        }
    }

    It 'resolves the MSP-wide key via Resolve-ImperionDattoBcdrApiKey' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDattoBcdrRequest { , @() }
            Get-ImperionDattoBcdrBackup | Out-Null
            Should -Invoke Resolve-ImperionDattoBcdrApiKey -Times 1
            Should -Invoke Invoke-ImperionDattoBcdrRequest -Times 1 -ParameterFilter { $ApiKey -eq 'resolved-key' }
        }
    }
}
