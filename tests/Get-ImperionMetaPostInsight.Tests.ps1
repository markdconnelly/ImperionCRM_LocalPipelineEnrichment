#Requires -Modules Pester
# Hermetic unit tests for Get-ImperionMetaPostInsight: per-metric isolation, entity_kind
# (post|media), end_time fallback, and external_id composition (slice H #357).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionMetaPostInsight' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'partner-tenant' } }
            Mock Write-ImperionLog { }
            Mock Resolve-ImperionMetaToken { 'tok' }
        }
    }

    It 'requests post metrics ONE AT A TIME with entity_kind=post' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionMetaRequest {
                if ($Uri -match 'insights\?metric=([^&]+)') {
                    $metric = $Matches[1]
                    @([pscustomobject]@{ name = $metric; period = 'lifetime'
                            values = @([pscustomobject]@{ value = 9; end_time = '2026-06-11T07:00:00+0000' }) })
                }
                else { @() }
            }
            $rows = @(Get-ImperionMetaPostInsight -PostId 'p1' -Token 't' -PostMetric 'post_impressions', 'post_clicks')
            Should -Invoke Invoke-ImperionMetaRequest -Times 1 -ParameterFilter { $Uri -eq 'p1/insights?metric=post_impressions&period=lifetime' }
            Should -Invoke Invoke-ImperionMetaRequest -Times 1 -ParameterFilter { $Uri -eq 'p1/insights?metric=post_clicks&period=lifetime' }
            $rows.Count | Should -Be 2
            ($rows | ForEach-Object entity_kind | Sort-Object -Unique) | Should -Be 'post'
            $rows[0].entity_external_id | Should -Be 'p1'
            $rows[0].external_id | Should -Be 'post:p1:post_impressions:lifetime:2026-06-11T07:00:00+0000'
            $rows[0].source | Should -Be 'meta'
        }
    }

    It 'a failing (deprecated) post metric warns and continues' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionMetaRequest {
                if ($Uri -match 'metric=post_dead') { throw 'HTTP 400 metric deprecated' }
                if ($Uri -match 'metric=post_clicks') {
                    @([pscustomobject]@{ name = 'post_clicks'; period = 'lifetime'
                            values = @([pscustomobject]@{ value = 3; end_time = '2026-06-11T07:00:00+0000' }) })
                }
                else { @() }
            }
            $rows = @(Get-ImperionMetaPostInsight -PostId 'p1' -Token 't' -PostMetric 'post_dead', 'post_clicks')
            $rows.Count | Should -Be 1
            $rows[0].metric | Should -Be 'post_clicks'
            Should -Invoke Write-ImperionLog -Times 1 -ParameterFilter { $Level -eq 'Warn' -and $Message -match 'post_dead' -and $Message -match 'continuing' }
        }
    }

    It 'collects IG media with entity_kind=media and dates a missing end_time to today' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionMetaRequest {
                if ($Uri -match 'metric=reach') {
                    @([pscustomobject]@{ name = 'reach'; period = 'lifetime'
                            values = @([pscustomobject]@{ value = 50 }) })   # no end_time
                }
                else { @() }
            }
            $rows = @(Get-ImperionMetaPostInsight -MediaId 'm1' -Token 't' -MediaMetric 'reach')
            $rows.Count | Should -Be 1
            $rows[0].entity_kind | Should -Be 'media'
            $rows[0].entity_external_id | Should -Be 'm1'
            $rows[0].external_id | Should -Match '^media:m1:reach:lifetime:\d{4}-\d{2}-\d{2}$'
        }
    }
}
