#Requires -Modules Pester
# Hermetic unit tests for Get-ImperionMetaInsight: per-metric isolation, external_id
# composition, the followers_count lifetime snapshot.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionMetaInsight' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'partner-tenant' } }
            Mock Write-ImperionLog { }
        }
    }

    It 'requests page metrics ONE AT A TIME and composes the snapshot external_id' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionMetaRequest {
                if ($Uri -match 'insights\?metric=([^&]+)') {
                    $metric = $Matches[1]
                    @([pscustomobject]@{
                            name   = $metric
                            period = 'day'
                            values = @([pscustomobject]@{ value = 42; end_time = '2026-06-11T07:00:00+0000' })
                        })
                }
                else { @() }
            }
            $rows = @(Get-ImperionMetaInsight -PageId 'page1' -Token 't' -PageMetric 'page_impressions', 'page_fans' -IgMetric @())
            # one insights call per metric + the IG-resolution page hop
            Should -Invoke Invoke-ImperionMetaRequest -Times 1 -ParameterFilter { $Uri -eq 'page1/insights?metric=page_impressions&period=day' }
            Should -Invoke Invoke-ImperionMetaRequest -Times 1 -ParameterFilter { $Uri -eq 'page1/insights?metric=page_fans&period=day' }

            $rows.Count | Should -Be 2
            $rows[0].entity_kind | Should -Be 'page'
            $rows[0].entity_external_id | Should -Be 'page1'
            $rows[0].metric | Should -Be 'page_impressions'
            $rows[0].period | Should -Be 'day'
            $rows[0].value | Should -Be '42'
            $rows[0].external_id | Should -Be 'page:page1:page_impressions:day:2026-06-11T07:00:00+0000'
            $rows[0].source | Should -Be 'meta'
            $rows[0].tenant_id | Should -Be 'partner-tenant'
        }
    }

    It 'a failing (deprecated) metric warns and continues - never aborts the run' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionMetaRequest {
                if ($Uri -match 'metric=page_dead_metric') { throw 'HTTP 400 (#100) metric deprecated' }
                if ($Uri -match 'insights\?metric=page_fans') {
                    @([pscustomobject]@{ name = 'page_fans'; period = 'day'
                            values = @([pscustomobject]@{ value = 7; end_time = '2026-06-11T07:00:00+0000' })
                        })
                }
                else { @() }
            }
            $rows = @(Get-ImperionMetaInsight -PageId 'page1' -Token 't' -PageMetric 'page_dead_metric', 'page_fans' -IgMetric @())
            $rows.Count | Should -Be 1
            $rows[0].metric | Should -Be 'page_fans'
            Should -Invoke Write-ImperionLog -Times 1 -ParameterFilter {
                $Level -eq 'Warn' -and $Message -match "page_dead_metric" -and $Message -match 'continuing'
            }
        }
    }

    It 'adds the IG followers_count lifetime snapshot row (resolved through the page)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionMetaRequest {
                if ($Uri -match 'instagram_business_account') {
                    @([pscustomobject]@{ instagram_business_account = [pscustomobject]@{ id = 'ig9' } })
                }
                elseif ($Uri -match 'followers_count') {
                    @([pscustomobject]@{ followers_count = 512 })
                }
                elseif ($Uri -match 'ig9/insights\?metric=reach') {
                    @([pscustomobject]@{ name = 'reach'; period = 'day'
                            values = @([pscustomobject]@{ value = 100; end_time = '2026-06-11T07:00:00+0000' })
                        })
                }
                else { @() }
            }
            $rows = @(Get-ImperionMetaInsight -PageId 'page1' -Token 't' -PageMetric @() -IgMetric 'reach')
            $rows.Count | Should -Be 2
            $reach = $rows | Where-Object metric -EQ 'reach'
            $reach.entity_kind | Should -Be 'ig_user'
            $reach.entity_external_id | Should -Be 'ig9'
            $followers = $rows | Where-Object metric -EQ 'followers_count'
            $followers.period | Should -Be 'lifetime'
            $followers.value | Should -Be '512'
            $followers.external_id | Should -Match '^ig_user:ig9:followers_count:lifetime:\d{4}-\d{2}-\d{2}$'
        }
    }

    It 'throws when neither -PageId nor -IgUserId is given' {
        InModuleScope ImperionPipeline {
            { Get-ImperionMetaInsight -Token 't' } | Should -Throw '*-PageId*'
        }
    }

    It 'page-metric defaults drop the deprecated names (#135)' {
        InModuleScope ImperionPipeline {
            $ast = (Get-Command Get-ImperionMetaInsight).ScriptBlock.Ast
            $param = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.ParameterAst] -and $n.Name.VariablePath.UserPath -eq 'PageMetric' }, $true)[0]
            $defaults = $param.DefaultValue.Extent.Text
            $defaults | Should -Not -Match 'page_impressions(?!_unique)'
            $defaults | Should -Not -Match 'page_fans'
            $defaults | Should -Match 'page_impressions_unique'
            $defaults | Should -Match 'page_post_engagements'
            $defaults | Should -Match 'page_views_total'
        }
    }

    It 'requests IG total_value metrics with metric_type=total_value and parses the total_value shape (#135)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionMetaRequest {
                if ($Uri -match 'ig9/insights\?metric=profile_views&period=day&metric_type=total_value') {
                    @([pscustomobject]@{ name = 'profile_views'; period = 'day'
                            total_value = [pscustomobject]@{ value = 88 }
                        })
                }
                elseif ($Uri -match 'followers_count') { @([pscustomobject]@{ followers_count = 5 }) }
                else { @() }
            }
            $rows = @(Get-ImperionMetaInsight -IgUserId 'ig9' -Token 't' -PageMetric @() -IgMetric @() -IgTotalValueMetric 'profile_views')
            Should -Invoke Invoke-ImperionMetaRequest -Times 1 -ParameterFilter {
                $Uri -eq 'ig9/insights?metric=profile_views&period=day&metric_type=total_value'
            }
            $pv = $rows | Where-Object metric -EQ 'profile_views'
            $pv | Should -Not -BeNullOrEmpty
            $pv.value | Should -Be '88'
            $pv.period | Should -Be 'day'
            $pv.entity_kind | Should -Be 'ig_user'
            $pv.external_id | Should -Match '^ig_user:ig9:profile_views:day:\d{4}-\d{2}-\d{2}$'
        }
    }
}
