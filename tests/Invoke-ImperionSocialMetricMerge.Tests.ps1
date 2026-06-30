#Requires -Modules Pester
# Hermetic unit tests for Invoke-ImperionSocialMetricMerge: ShouldProcess gating, the
# normalized metric-name mapping (#135), platform derivation, and the 0075 idempotency key.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionSocialMetricMerge' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection {
                [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            }
        }
    }

    It 'honors -WhatIf: no connection, no SQL' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbNonQuery { 0 }
            Invoke-ImperionSocialMetricMerge -WhatIf | Out-Null
            Should -Invoke Invoke-ImperionDbNonQuery -Times 0
            Should -Invoke New-ImperionDbConnection -Times 0
        }
    }

    Context 'merge SQL contracts' {
        BeforeEach {
            InModuleScope ImperionPipeline {
                $script:capturedMergeSql = [System.Collections.Generic.List[string]]::new()
                Mock Invoke-ImperionDbNonQuery { $script:capturedMergeSql.Add($Sql); 1 }
            }
        }

        It 'runs one social_metric merge and returns the tally' {
            InModuleScope ImperionPipeline {
                $tally = Invoke-ImperionSocialMetricMerge -Confirm:$false
                $script:capturedMergeSql.Count | Should -Be 1
                $tally.social_metrics_merged | Should -Be 1
                Should -Invoke Write-ImperionLog -Times 1 -ParameterFilter { $Level -eq 'Metric' -and $Message -match 'Merge plan complete' }
            }
        }

        It 'normalizes raw metric names onto the canonical vocabulary (#135)' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionSocialMetricMerge -Confirm:$false | Out-Null
                $sql = $script:capturedMergeSql[0]
                # a representative sample of the raw → canonical collapses
                $sql | Should -Match "WHEN 'page_impressions_unique' THEN 'impressions'"
                $sql | Should -Match "WHEN 'page_post_engagements' THEN 'engagement'"
                $sql | Should -Match "WHEN 'page_fans' THEN 'follower_count'"
                $sql | Should -Match "WHEN 'followers_count' THEN 'follower_count'"
                $sql | Should -Match "WHEN 'spend' THEN 'spend'"
                $sql | Should -Match "WHEN 'inline_link_clicks' THEN 'clicks'"
                # un-mapped names pass through lower-cased, never dropped
                $sql | Should -Match 'ELSE lower\(b\.metric\) END'
            }
        }

        It 'derives platform from entity_kind incl. the paid meta_ads plane' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionSocialMetricMerge -Confirm:$false | Out-Null
                $sql = $script:capturedMergeSql[0]
                $sql | Should -Match "WHEN b\.entity_kind = 'page' THEN 'facebook'"
                $sql | Should -Match "WHEN b\.entity_kind IN \('ig_user', 'media'\) THEN 'instagram'"
                $sql | Should -Match "WHEN b\.entity_kind = 'post' THEN 'facebook'"
                $sql | Should -Match "WHEN b\.entity_kind IN \('ad', 'campaign', 'adset', 'adaccount'\) THEN 'meta_ads'"
            }
        }

        It 'is ON CONFLICT DO NOTHING on the 0075 unique key and guards the numeric cast' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionSocialMetricMerge -Confirm:$false | Out-Null
                $sql = $script:capturedMergeSql[0]
                $sql | Should -Match 'INSERT INTO social_metric'
                $sql | Should -Match 'ON CONFLICT \(platform, entity_kind, entity_external_id, metric, period, captured_at\) DO NOTHING'
                $sql | Should -Match ([regex]::Escape("CASE WHEN b.value ~ '^-?\d+(\.\d+)?`$' THEN b.value::numeric END"))
                # period NOT NULL guard (a NULL period would defeat ON CONFLICT)
                $sql | Should -Match 'b\.period IS NOT NULL'
            }
        }

        It 'reuses a passed connection without disposing it' {
            InModuleScope ImperionPipeline {
                $disposed = @{ v = $false }
                $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { $disposed.v = $true }.GetNewClosure()
                Invoke-ImperionSocialMetricMerge -Connection $conn -Confirm:$false | Out-Null
                Should -Invoke New-ImperionDbConnection -Times 0
                $disposed.v | Should -BeFalse
            }
        }
    }
}

Describe 'Get-ImperionSocialMetricCanonSql' {
    It 'maps every documented raw synonym onto its canonical name' {
        InModuleScope ImperionPipeline {
            $sql = Get-ImperionSocialMetricCanonSql -Column 'b.metric'
            $sql | Should -Match '^CASE lower\(b\.metric\)'
            $sql | Should -Match 'ELSE lower\(b\.metric\) END$'
            # paid + organic both represented
            $sql | Should -Match "WHEN 'impressions' THEN 'impressions'"
            $sql | Should -Match "WHEN 'reach' THEN 'reach'"
            $sql | Should -Match "WHEN 'cpc' THEN 'cpc'"
        }
    }

    It 'honors a custom column reference' {
        InModuleScope ImperionPipeline {
            $sql = Get-ImperionSocialMetricCanonSql -Column 'x.metric'
            $sql | Should -Match '^CASE lower\(x\.metric\)'
            $sql | Should -Match 'ELSE lower\(x\.metric\) END$'
        }
    }
}
