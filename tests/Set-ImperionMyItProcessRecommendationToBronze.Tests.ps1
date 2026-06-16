#Requires -Modules Pester
# Hermetic unit tests for Set-ImperionMyItProcessRecommendationToBronze (adapter over the scaffold).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionMyItProcessRecommendationToBronze' {
    BeforeEach {
        InModuleScope ImperionPipeline { Mock Write-ImperionLog { } }
    }

    It 'projects rows to the myitprocess_recommendations column set and upserts on external_id' {
        InModuleScope ImperionPipeline {
            $captured = @{}
            Mock Invoke-ImperionBronzeUpsert { $captured.Table = $Table; $captured.Rows = $Rows; [pscustomobject]@{ scanned = 1; inserted = 1; updated = 0; unchanged = 0 } }
            $row = [pscustomobject]@{
                account_ref = 'ACC-9'; assessment_name = 'Review'; recommendation_title = 'MFA'; category = 'Security'
                priority = 'High'; status = 'Open'; target_date = '2026-09-01'
                tenant_id = 't1'; source = 'myitprocess'; external_id = 'REC-1'; collected_at = 'now'; raw_payload = '{}'; content_hash = 'h'
                strayCollectorField = 'dropped-from-flat'
            }
            $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            $tally = $row | Set-ImperionMyItProcessRecommendationToBronze -Connection $conn
            $tally.inserted | Should -Be 1
            $captured.Table | Should -Be 'myitprocess_recommendations'
            $captured.Rows[0].external_id | Should -Be 'REC-1'
            $captured.Rows[0].recommendation_title | Should -Be 'MFA'
            $captured.Rows[0].PSObject.Properties.Name | Should -Not -Contain 'strayCollectorField'
        }
    }

    It 'returns the zero tally on empty input without touching the database' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionBronzeUpsert { }
            $tally = @() | Set-ImperionMyItProcessRecommendationToBronze
            $tally.scanned | Should -Be 0
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }

    It 'honors -WhatIf (no upsert)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionBronzeUpsert { }
            $row = [pscustomobject]@{ recommendation_title = 'MFA'; tenant_id = 't'; source = 'myitprocess'; external_id = 'REC-1'; collected_at = 'n'; raw_payload = '{}'; content_hash = 'h' }
            $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            $row | Set-ImperionMyItProcessRecommendationToBronze -Connection $conn -WhatIf | Out-Null
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}
