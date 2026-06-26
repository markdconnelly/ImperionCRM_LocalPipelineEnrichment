#Requires -Modules Pester
# Hermetic tests for Invoke-ImperionTenantHydration (#359, ADR-0030 Decision #4): the tenant-outer
# 365 estate driver. The registry, the token acquire, the collector routines, and logging are all
# mocked — no live Graph/DB. Asserts tenant-outer ordering, one-token-per-tenant acquire, and the
# two isolation guards (skip an unconsented tenant whole; survive a single routine throwing).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionTenantHydration' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog {}
            Mock Get-ImperionGraphToken { 'fake-token' }
            # Two stand-in routines (so the test does not depend on the 14 real collectors).
            function Invoke-ImperionTestRoutineA { param([string] $TenantId) }
            function Invoke-ImperionTestRoutineB { param([string] $TenantId) }
            Mock Invoke-ImperionTestRoutineA {}
            Mock Invoke-ImperionTestRoutineB {}
        }
    }

    It 'runs every routine for a tenant before moving to the next, each pinned with -TenantId (tenant-outer)' {
        InModuleScope ImperionPipeline {
            # Record the (routine, tenant) call order in the mock bodies. Asserting the exact
            # sequence proves BOTH that each routine ran once per tenant pinned to that tenant AND
            # the tenant-OUTER ordering (all of tenant-a's routines, then tenant-b's). (Recording in
            # the mock body — not -ParameterFilter — because the driver dispatches via `& $routine`,
            # through which Pester does not surface the bound param to a -ParameterFilter block.)
            $script:hydrationCalls = [System.Collections.Generic.List[string]]::new()
            Mock Invoke-ImperionTestRoutineA { $script:hydrationCalls.Add("A:$TenantId") }
            Mock Invoke-ImperionTestRoutineB { $script:hydrationCalls.Add("B:$TenantId") }

            Invoke-ImperionTenantHydration -TenantId 'tenant-a', 'tenant-b' `
                -Routine 'Invoke-ImperionTestRoutineA', 'Invoke-ImperionTestRoutineB'

            $script:hydrationCalls | Should -Be @('A:tenant-a', 'B:tenant-a', 'A:tenant-b', 'B:tenant-b')
        }
    }

    It 'acquires the Graph token ONCE per tenant up front (token reuse across routines)' {
        InModuleScope ImperionPipeline {
            Invoke-ImperionTenantHydration -TenantId 'tenant-a', 'tenant-b' `
                -Routine 'Invoke-ImperionTestRoutineA', 'Invoke-ImperionTestRoutineB'
            # One acquire per tenant — NOT one per (tenant, routine).
            Should -Invoke Get-ImperionGraphToken -Times 2
            Should -Invoke Get-ImperionGraphToken -Times 1 -ParameterFilter { $TenantId -eq 'tenant-a' }
        }
    }

    It 'defaults the tenant list to the consented-tenant registry' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConsentedTenant { @('reg-a') }
            Invoke-ImperionTenantHydration -Routine 'Invoke-ImperionTestRoutineA'
            Should -Invoke Get-ImperionConsentedTenant -Times 1
            Should -Invoke Invoke-ImperionTestRoutineA -Times 1 -ParameterFilter { $TenantId -eq 'reg-a' }
        }
    }

    It 'skips a tenant whole when its token acquire fails (fail-closed), and continues the rest' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionGraphToken { if ($TenantId -eq 'bad') { throw 'no consent' } else { 'fake-token' } }
            Invoke-ImperionTenantHydration -TenantId 'bad', 'good' -Routine 'Invoke-ImperionTestRoutineA'

            # No routine ran for the unconsented tenant; the good tenant still hydrated.
            Should -Invoke Invoke-ImperionTestRoutineA -Times 0 -ParameterFilter { $TenantId -eq 'bad' }
            Should -Invoke Invoke-ImperionTestRoutineA -Times 1 -ParameterFilter { $TenantId -eq 'good' }
            Should -Invoke Write-ImperionLog -Times 1 -ParameterFilter {
                $Level -eq 'Metric' -and $Data.tenants_skipped -eq 1 -and $Data.tenants_hydrated -eq 1
            }
        }
    }

    It 'isolates a single routine failure — the other routines for that tenant still run' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionTestRoutineA { throw 'graph blip' }
            Invoke-ImperionTenantHydration -TenantId 'tenant-a' `
                -Routine 'Invoke-ImperionTestRoutineA', 'Invoke-ImperionTestRoutineB'

            Should -Invoke Invoke-ImperionTestRoutineB -Times 1 -ParameterFilter { $TenantId -eq 'tenant-a' }
            Should -Invoke Write-ImperionLog -Times 1 -ParameterFilter {
                $Level -eq 'Metric' -and $Data.routine_failures -eq 1 -and $Data.tenants_hydrated -eq 1
            }
        }
    }

    It 'warns and does nothing when no consented tenants are mapped (dormant-safe)' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConsentedTenant { @() }
            Invoke-ImperionTenantHydration -Routine 'Invoke-ImperionTestRoutineA'
            Should -Invoke Invoke-ImperionTestRoutineA -Times 0
            Should -Invoke Get-ImperionGraphToken -Times 0
            Should -Invoke Write-ImperionLog -Times 1 -ParameterFilter { $Level -eq 'Warn' }
        }
    }
}
