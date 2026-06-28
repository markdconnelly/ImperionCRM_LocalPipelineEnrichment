#Requires -Modules Pester
# Hermetic unit tests for Get-ImperionMetaAdInsight: ad-account resolution / fail-soft, the
# metric-field pivot into meta_insights rows, and external_id composition (slice H #357).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionMetaAdInsight' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'partner-tenant' } }
            Mock Write-ImperionLog { }
            Mock Resolve-ImperionMetaToken { 'tok' }
        }
    }

    AfterEach { $env:IMPERION_META_AD_ACCOUNT_ID = $null }

    It 'returns nothing and warns when no ad account is configured (fail-soft)' {
        InModuleScope ImperionPipeline {
            $env:IMPERION_META_AD_ACCOUNT_ID = $null
            Mock Invoke-ImperionMetaRequest { @() }
            $rows = @(Get-ImperionMetaAdInsight -Token 't')
            $rows.Count | Should -Be 0
            Should -Invoke Invoke-ImperionMetaRequest -Times 0
            Should -Invoke Write-ImperionLog -Times 1 -ParameterFilter { $Level -eq 'Warn' -and $Message -match 'no ad account' }
        }
    }

    It 'prefixes act_ and pivots each metric FIELD into a meta_insights row with entity_kind=level' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionMetaRequest {
                @([pscustomobject]@{
                        campaign_id = 'c1'; spend = '12.50'; impressions = '1000'; clicks = '20'
                        date_start = '2026-06-01'; date_stop = '2026-06-30'
                    })
            }
            $rows = @(Get-ImperionMetaAdInsight -AdAccountId '123' -Level campaign -Metric 'spend', 'impressions', 'clicks' -Token 't')
            Should -Invoke Invoke-ImperionMetaRequest -Times 1 -ParameterFilter { $Uri -match '^act_123/insights\?level=campaign' }
            $rows.Count | Should -Be 3
            ($rows | ForEach-Object entity_kind | Sort-Object -Unique) | Should -Be 'campaign'
            ($rows | ForEach-Object entity_external_id | Sort-Object -Unique) | Should -Be 'c1'
            $spend = $rows | Where-Object metric -EQ 'spend'
            $spend.value | Should -Be '12.50'
            $spend.period | Should -Be 'last_30d'
            $spend.external_id | Should -Be 'campaign:c1:spend:last_30d:2026-06-30'
            $spend.source | Should -Be 'meta'
            $spend.tenant_id | Should -Be 'partner-tenant'
        }
    }

    It 'skips metrics absent on an entity (no garbage zero rows)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionMetaRequest {
                @([pscustomobject]@{ ad_id = 'a1'; spend = '5'; date_stop = '2026-06-30' })  # impressions absent
            }
            $rows = @(Get-ImperionMetaAdInsight -AdAccountId 'act_9' -Level ad -Metric 'spend', 'impressions' -Token 't')
            $rows.Count | Should -Be 1
            $rows[0].metric | Should -Be 'spend'
            $rows[0].entity_kind | Should -Be 'ad'
        }
    }
}
