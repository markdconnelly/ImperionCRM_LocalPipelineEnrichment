#Requires -Modules Pester
# Hermetic tests for Get-ImperionSentinelObject: ARM token + requests mocked, routed by path.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionSentinelObject' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'partner' } }
            Mock Get-ImperionArmToken { 'arm-token' }
            Mock Write-ImperionLog {}
            Mock Invoke-ImperionArmRequest {
                switch -Regex ($Path) {
                    '^/subscriptions\?' { return @([pscustomobject]@{ subscriptionId = 'sub-1'; displayName = 'Prod' }) }
                    'OperationalInsights/workspaces\?' {
                        return @(
                            [pscustomobject]@{ name = 'ws-sec'; id = '/subscriptions/sub-1/resourceGroups/rg-sec/providers/Microsoft.OperationalInsights/workspaces/ws-sec' }
                            [pscustomobject]@{ name = 'ws-plain'; id = '/subscriptions/sub-1/resourceGroups/rg-app/providers/Microsoft.OperationalInsights/workspaces/ws-plain' }
                        )
                    }
                    'ws-sec/providers/Microsoft\.SecurityInsights/alertRules' {
                        return @([pscustomobject]@{
                            id = '/sub/.../alertRules/ar-1'; name = 'ar-1'; kind = 'Scheduled'
                            properties = [pscustomobject]@{ displayName = 'Brute force'; enabled = $true; severity = 'High'; tactics = @('CredentialAccess', 'InitialAccess'); lastModifiedUtc = '2026-06-01T00:00:00Z' }
                        })
                    }
                    'ws-plain/providers/Microsoft\.SecurityInsights/alertRules' { throw 'no SecurityInsights on this workspace' }
                    'ws-sec/providers/Microsoft\.SecurityInsights/automationRules' {
                        return @([pscustomobject]@{ id = '/sub/.../automationRules/au-1'; properties = [pscustomobject]@{ displayName = 'Auto-close'; order = 1 } })
                    }
                    'ws-sec/providers/Microsoft\.SecurityInsights/watchlists' {
                        return @([pscustomobject]@{ id = '/sub/.../watchlists/wl-1'; properties = [pscustomobject]@{ displayName = 'VIPs'; provider = 'Imperion'; source = 'csv'; updated = '2026-06-02T00:00:00Z' } })
                    }
                    'Microsoft\.Insights/workbooks' {
                        return @([pscustomobject]@{ id = '/sub/.../workbooks/wb-1'; properties = [pscustomobject]@{ displayName = 'Sentinel ops'; category = 'sentinel'; version = '1.0'; timeModified = '2026-06-03T00:00:00Z' } })
                    }
                    default { return @() }
                }
            }
        }
    }

    It 'collects all four entity sets, stamped with entity + workspace/subscription context' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionSentinelObject)
            ($rows | Where-Object { $_.entity -eq 'analytic_rules' }).Count   | Should -Be 1
            ($rows | Where-Object { $_.entity -eq 'automation_rules' }).Count | Should -Be 1
            ($rows | Where-Object { $_.entity -eq 'watchlists' }).Count       | Should -Be 1
            ($rows | Where-Object { $_.entity -eq 'workbooks' }).Count        | Should -Be 1

            $rule = $rows | Where-Object { $_.entity -eq 'analytic_rules' }
            $rule.display_name | Should -Be 'Brute force'
            $rule.rule_kind    | Should -Be 'Scheduled'
            $rule.tactics      | Should -Be 'CredentialAccess; InitialAccess'
            $rule.workspace    | Should -Be 'ws-sec'
            $rule.source       | Should -Be 'sentinel'
            $rule.tenant_id    | Should -Be 'partner'
            $rule.external_id  | Should -Be '/sub/.../alertRules/ar-1'
            $rule.content_hash | Should -Match '^[0-9a-f]{64}$'

            ($rows | Where-Object { $_.entity -eq 'workbooks' }).subscription_id | Should -Be 'sub-1'
        }
    }

    It 'skips a workspace without Sentinel (logs, no throw) and never queries its other objects' {
        InModuleScope ImperionPipeline {
            { Get-ImperionSentinelObject } | Should -Not -Throw
            Should -Invoke Invoke-ImperionArmRequest -Times 0 -ParameterFilter { $Path -match 'ws-plain.*automationRules' }
            Should -Invoke Write-ImperionLog -ParameterFilter { $Message -like 'Workspace ws-plain: no Sentinel*' }
        }
    }

    It 'warns and continues when the workbook query fails' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionArmRequest {
                switch -Regex ($Path) {
                    '^/subscriptions\?' { return @([pscustomobject]@{ subscriptionId = 'sub-1' }) }
                    'OperationalInsights/workspaces\?' { return @() }
                    'Microsoft\.Insights/workbooks' { throw 'workbooks API not registered' }
                    default { return @() }
                }
            }
            { Get-ImperionSentinelObject } | Should -Not -Throw
            Should -Invoke Write-ImperionLog -ParameterFilter { $Level -eq 'Warn' -and $Message -like 'Workbook query failed*' }
        }
    }
}
