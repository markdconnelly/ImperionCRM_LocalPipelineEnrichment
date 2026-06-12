#Requires -Modules Pester
# Hermetic unit tests for Set-ImperionKqmProposalToBronze (adapter over Invoke-ImperionBronzePost).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionKqmProposalToBronze' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
        }
    }

    It 'projects rows to the migration-0038 kqm_proposals column set and upserts' {
        InModuleScope ImperionPipeline {
            $captured = @{}
            Mock Invoke-ImperionBronzeUpsert { $captured.Table = $Table; $captured.Rows = $Rows; [pscustomobject]@{ scanned = 1; inserted = 1; updated = 0; unchanged = 0 } }
            $row = [pscustomobject]@{
                name = 'Q'; status = 'open'; total = '10'; account_ref = 'Acme'; created_at = 'c'; updated_at = 'u'
                tenant_id = 't1'; source = 'kqm'; external_id = '7'; collected_at = 'now'; raw_payload = '{}'; content_hash = 'h'
                strayCollectorField = 'dropped-from-flat'
            }
            $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            $tally = $row | Set-ImperionKqmProposalToBronze -Connection $conn
            $tally.inserted | Should -Be 1
            $captured.Table | Should -Be 'kqm_proposals'
            $captured.Rows[0].name | Should -Be 'Q'
            $captured.Rows[0].PSObject.Properties.Name | Should -Not -Contain 'strayCollectorField'
        }
    }

    It 'returns the zero tally on empty input without touching the database' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionBronzeUpsert { }
            $tally = @() | Set-ImperionKqmProposalToBronze
            $tally.scanned | Should -Be 0
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }

    It 'honors -WhatIf (no upsert)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionBronzeUpsert { }
            $row = [pscustomobject]@{ name = 'Q'; tenant_id = 't'; source = 'kqm'; external_id = '1'; collected_at = 'n'; raw_payload = '{}'; content_hash = 'h' }
            $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            $row | Set-ImperionKqmProposalToBronze -Connection $conn -WhatIf | Out-Null
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
