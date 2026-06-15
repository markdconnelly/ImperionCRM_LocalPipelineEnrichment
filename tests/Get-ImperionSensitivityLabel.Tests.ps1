#Requires -Modules Pester
# Hermetic tests for Get-ImperionSensitivityLabel: Graph token + request mocked (issue #141).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionSensitivityLabel' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'partner' } }
            Mock Get-ImperionGraphToken { 'graph-token' }
            Mock Write-ImperionLog {}
            Mock Invoke-ImperionGraphRequest {
                @(
                    [pscustomobject]@{
                        id = 'label-conf'; name = 'Confidential'; displayName = 'Confidential'
                        description = 'Sensitive business data'; isActive = $true; isAppendable = $false
                        sensitivity = 2; tooltip = 'Restrict sharing'; appliesTo = 'email'
                        parent = $null
                    }
                    [pscustomobject]@{
                        id = 'label-conf-internal'; name = 'Internal'; displayName = 'Confidential\Internal'
                        isActive = $true; sensitivity = 3
                        parent = [pscustomobject]@{ id = 'label-conf'; name = 'Confidential' }
                    }
                )
            }
        }
    }

    It 'flattens /sensitivityLabels to the schema-259 columns + standard envelope (id = the GUID)' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionSensitivityLabel)
            $rows.Count | Should -Be 2

            $conf = $rows | Where-Object { $_.external_id -eq 'label-conf' }
            $conf.label_name   | Should -Be 'Confidential'
            $conf.is_active    | Should -Be 'true'
            $conf.is_appendable | Should -Be 'false'
            $conf.applies_to   | Should -Be 'email'
            $conf.source       | Should -Be 'm365'
            $conf.tenant_id    | Should -Be 'partner'
            $conf.content_hash | Should -Match '^[0-9a-f]{64}$'
        }
    }

    It 'surfaces the parent label id for a sublabel' {
        InModuleScope ImperionPipeline {
            $sub = @(Get-ImperionSensitivityLabel) | Where-Object { $_.external_id -eq 'label-conf-internal' }
            $sub.parent_label_id   | Should -Be 'label-conf'
            $sub.parent_label_name | Should -Be 'Confidential'
        }
    }

    It 'calls the sensitivityLabels endpoint' {
        InModuleScope ImperionPipeline {
            Get-ImperionSensitivityLabel | Out-Null
            Should -Invoke Invoke-ImperionGraphRequest -Times 1 -ParameterFilter {
                $Uri -eq 'https://graph.microsoft.com/v1.0/security/informationProtection/sensitivityLabels'
            }
        }
    }

    It 'does not throw when a label omits optional fields (StrictMode-safe)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest { @([pscustomobject]@{ id = 'bare'; name = 'Public' }) }
            { Get-ImperionSensitivityLabel } | Should -Not -Throw
            (@(Get-ImperionSensitivityLabel)[0]).parent_label_id | Should -BeNullOrEmpty
        }
    }

    It 'collects from the requested tenant (GDAP)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest { , @() }
            Get-ImperionSensitivityLabel -TenantId 'customer-9' | Out-Null
            Should -Invoke Get-ImperionGraphToken -Times 1 -ParameterFilter { $TenantId -eq 'customer-9' }
        }
    }
}
