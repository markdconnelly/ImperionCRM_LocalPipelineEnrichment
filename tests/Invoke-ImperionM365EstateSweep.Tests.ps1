#Requires -Modules Pester
# Hermetic tests for Invoke-ImperionM365EstateSweep (#266): the m365 estate fan-out with
# absolute per-tenant fail-isolation. The per-tenant collector is supplied as a script block
# and logging is mocked — no live Graph/DB. Mirrors the LP #234 Invoke-ImperionCloudResourceSync
# precedent these tasks now share.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionM365EstateSweep' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog {}
            # Default: the registry returns nothing, so the existing env-driven + dormant-safe
            # tests behave exactly as before (env set => env wins; env empty => $null partner run).
            # The registry-path tests below override this mock. Mocking it also keeps these tests
            # hermetic — no DB connection is opened.
            Mock Get-ImperionConsentedTenant { @() }
        }
        $env:IMPERION_M365_TENANT_IDS = ''
    }

    AfterAll {
        $env:IMPERION_M365_TENANT_IDS = ''
    }

    It 'fans out over every tenant in IMPERION_M365_TENANT_IDS (trimmed)' {
        InModuleScope ImperionPipeline {
            $env:IMPERION_M365_TENANT_IDS = 'tenant-a, tenant-b ,tenant-c'
            $script:seenTenants = [System.Collections.Generic.List[object]]::new()
            Invoke-ImperionM365EstateSweep -Label 'test' -PerTenant {
                param($TenantId) $script:seenTenants.Add($TenantId)
            }
            $script:seenTenants | Should -Be @('tenant-a', 'tenant-b', 'tenant-c')
        }
    }

    It 'is dormant-safe: with no tenant list it runs the partner tenant once (TenantId = $null)' {
        InModuleScope ImperionPipeline {
            $env:IMPERION_M365_TENANT_IDS = ''
            $script:seenTenants = [System.Collections.Generic.List[object]]::new()
            Invoke-ImperionM365EstateSweep -Label 'test' -PerTenant {
                param($TenantId) $script:seenTenants.Add($TenantId)
            }
            $script:seenTenants.Count | Should -Be 1
            $script:seenTenants[0] | Should -BeNullOrEmpty
        }
    }

    It 'skips a failing tenant and continues (per-tenant isolation, fail-closed)' {
        InModuleScope ImperionPipeline {
            $env:IMPERION_M365_TENANT_IDS = 'bad,good'
            $script:processed = [System.Collections.Generic.List[object]]::new()
            { Invoke-ImperionM365EstateSweep -Label 'test' -PerTenant {
                    param($TenantId)
                    if ($TenantId -eq 'bad') { throw 'no consent' }
                    $script:processed.Add($TenantId)
                } } | Should -Not -Throw
            # The good tenant still ran even though the first tenant threw.
            $script:processed | Should -Be @('good')
            Should -Invoke Write-ImperionLog -Times 1 -ParameterFilter { $Level -eq 'Warn' }
        }
    }

    It 'reports swept/skipped counts in one Metric line' {
        InModuleScope ImperionPipeline {
            $env:IMPERION_M365_TENANT_IDS = 'bad,good'
            Invoke-ImperionM365EstateSweep -Label 'test' -PerTenant {
                param($TenantId)
                if ($TenantId -eq 'bad') { throw 'no consent' }
            }
            Should -Invoke Write-ImperionLog -Times 1 -ParameterFilter {
                $Level -eq 'Metric' -and $Data.tenants_registered -eq 2 -and
                $Data.tenants_swept -eq 1 -and $Data.tenants_skipped -eq 1
            }
        }
    }

    It 'honors an explicit -TenantId and ignores the env var' {
        InModuleScope ImperionPipeline {
            $env:IMPERION_M365_TENANT_IDS = 'env-tenant'
            $script:seenTenants = [System.Collections.Generic.List[object]]::new()
            Invoke-ImperionM365EstateSweep -Label 'test' -TenantId 'explicit-tenant' -PerTenant {
                param($TenantId) $script:seenTenants.Add($TenantId)
            }
            $script:seenTenants | Should -Be @('explicit-tenant')
        }
    }

    It 'defaults to the consented-tenant registry when the env var is unset (GUI-as-enable)' {
        InModuleScope ImperionPipeline {
            $env:IMPERION_M365_TENANT_IDS = ''
            Mock Get-ImperionConsentedTenant { @('reg-a', 'reg-b') }
            $script:seenTenants = [System.Collections.Generic.List[object]]::new()
            Invoke-ImperionM365EstateSweep -Label 'test' -PerTenant {
                param($TenantId) $script:seenTenants.Add($TenantId)
            }
            $script:seenTenants | Should -Be @('reg-a', 'reg-b')
            Should -Invoke Get-ImperionConsentedTenant -Times 1
        }
    }

    It 'lets IMPERION_M365_TENANT_IDS pin/override the registry when set (no registry read)' {
        InModuleScope ImperionPipeline {
            $env:IMPERION_M365_TENANT_IDS = 'pinned-tenant'
            Mock Get-ImperionConsentedTenant { @('reg-a', 'reg-b') }
            $script:seenTenants = [System.Collections.Generic.List[object]]::new()
            Invoke-ImperionM365EstateSweep -Label 'test' -PerTenant {
                param($TenantId) $script:seenTenants.Add($TenantId)
            }
            $script:seenTenants | Should -Be @('pinned-tenant')
            Should -Invoke Get-ImperionConsentedTenant -Times 0
        }
    }

    It 'is dormant-safe when both the env var and the registry are empty (partner tenant once)' {
        InModuleScope ImperionPipeline {
            $env:IMPERION_M365_TENANT_IDS = ''
            Mock Get-ImperionConsentedTenant { @() }
            $script:seenTenants = [System.Collections.Generic.List[object]]::new()
            Invoke-ImperionM365EstateSweep -Label 'test' -PerTenant {
                param($TenantId) $script:seenTenants.Add($TenantId)
            }
            $script:seenTenants.Count | Should -Be 1
            $script:seenTenants[0] | Should -BeNullOrEmpty
        }
    }

    It 'tags Warn/Metric logs with the supplied -Source (e.g. the Defender task)' {
        InModuleScope ImperionPipeline {
            $env:IMPERION_M365_TENANT_IDS = 'bad'
            Invoke-ImperionM365EstateSweep -Source 'defender' -Label 'Defender XDR' -PerTenant {
                param($TenantId) throw 'gated'
            }
            Should -Invoke Write-ImperionLog -Times 1 -ParameterFilter { $Level -eq 'Warn' -and $Source -eq 'defender' }
            Should -Invoke Write-ImperionLog -Times 1 -ParameterFilter { $Level -eq 'Metric' -and $Source -eq 'defender' }
        }
    }
}
