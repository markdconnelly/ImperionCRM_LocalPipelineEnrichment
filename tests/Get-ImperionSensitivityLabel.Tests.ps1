#Requires -Modules Pester
# Hermetic tests for Get-ImperionSensitivityLabel: Graph token + request mocked (issue #141/#375).
# Sensitivity labels are app-only ONLY per-user, so the collector resolves member users then
# evaluates the published labels for the first that returns any (#375).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionSensitivityLabel' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'partner' } }
            Mock Get-ImperionGraphToken { 'graph-token' }
            Mock Write-ImperionLog {}
            # User directory probe → one member.
            Mock Invoke-ImperionGraphRequest -ParameterFilter { $Uri -match 'v1\.0/users\?' } {
                @([pscustomobject]@{ id = 'u1'; userType = 'Member' })
            }
            # Per-user published labels.
            Mock Invoke-ImperionGraphRequest -ParameterFilter { $Uri -match 'sensitivityLabels' } {
                @(
                    [pscustomobject]@{
                        id = 'label-conf'; name = 'Confidential'; displayName = 'Confidential'
                        description = 'Sensitive business data'; isActive = $true; isAppendable = $false
                        sensitivity = 2; tooltip = 'Restrict sharing'; appliesTo = 'email'; parent = $null
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

    It 'flattens per-user labels to the applied #575 columns + standard envelope (id = the GUID)' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionSensitivityLabel)
            $rows.Count | Should -Be 2

            $conf = $rows | Where-Object { $_.external_id -eq 'label-conf' }
            $conf.label_id     | Should -Be 'label-conf'
            $conf.name         | Should -Be 'Confidential'
            $conf.priority     | Should -Be '2'
            $conf.is_active    | Should -Be 'true'
            $conf.source       | Should -Be 'm365'
            $conf.tenant_id    | Should -Be 'partner'
            $conf.content_hash | Should -Match '^[0-9a-f]{64}$'
        }
    }

    It 'maps priority from the Graph sensitivity ordering for a sublabel' {
        InModuleScope ImperionPipeline {
            $sub = @(Get-ImperionSensitivityLabel) | Where-Object { $_.external_id -eq 'label-conf-internal' }
            $sub.label_id | Should -Be 'label-conf-internal'
            $sub.priority | Should -Be '3'
        }
    }

    It 'evaluates labels via the per-user beta endpoint, not the tenant-root path (#375)' {
        InModuleScope ImperionPipeline {
            Get-ImperionSensitivityLabel | Out-Null
            Should -Invoke Invoke-ImperionGraphRequest -Times 1 -ParameterFilter {
                $Uri -eq 'https://graph.microsoft.com/beta/users/u1/security/informationProtection/sensitivityLabels'
            }
        }
    }

    It 'skips a label missing id (NOT NULL label_id, #375) without dropping the rest' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest -ParameterFilter { $Uri -match 'sensitivityLabels' } {
                @(
                    [pscustomobject]@{ name = 'Ghost'; sensitivity = 1 }      # no id
                    [pscustomobject]@{ id = 'label-pub'; name = 'Public'; sensitivity = 0 }
                )
            }
            $rows = @(Get-ImperionSensitivityLabel)
            $rows.Count | Should -Be 1
            $rows[0].external_id | Should -Be 'label-pub'
        }
    }

    It 'probes the next member when the first user returns no labels' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest -ParameterFilter { $Uri -match 'v1\.0/users\?' } {
                @(
                    [pscustomobject]@{ id = 'u1'; userType = 'Member' },
                    [pscustomobject]@{ id = 'u2'; userType = 'Member' }
                )
            }
            Mock Invoke-ImperionGraphRequest -ParameterFilter { $Uri -match '/users/u1/' } { @() }
            Mock Invoke-ImperionGraphRequest -ParameterFilter { $Uri -match '/users/u2/' } {
                @([pscustomobject]@{ id = 'label-x'; name = 'X'; sensitivity = 1 })
            }
            $rows = @(Get-ImperionSensitivityLabel)
            $rows.Count | Should -Be 1
            $rows[0].external_id | Should -Be 'label-x'
            Should -Invoke Invoke-ImperionGraphRequest -Times 1 -ParameterFilter { $Uri -match '/users/u1/' }
            Should -Invoke Invoke-ImperionGraphRequest -Times 1 -ParameterFilter { $Uri -match '/users/u2/' }
        }
    }

    It 'skips guest users when probing' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest -ParameterFilter { $Uri -match 'v1\.0/users\?' } {
                @(
                    [pscustomobject]@{ id = 'g1'; userType = 'Guest' },
                    [pscustomobject]@{ id = 'm1'; userType = 'Member' }
                )
            }
            Mock Invoke-ImperionGraphRequest -ParameterFilter { $Uri -match '/users/m1/' } {
                @([pscustomobject]@{ id = 'label-m'; name = 'M'; sensitivity = 1 })
            }
            Get-ImperionSensitivityLabel | Out-Null
            Should -Invoke Invoke-ImperionGraphRequest -Times 0 -ParameterFilter { $Uri -match '/users/g1/' }
            Should -Invoke Invoke-ImperionGraphRequest -Times 1 -ParameterFilter { $Uri -match '/users/m1/' }
        }
    }

    It 'does not throw when a label omits optional fields (StrictMode-safe)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest -ParameterFilter { $Uri -match 'sensitivityLabels' } {
                @([pscustomobject]@{ id = 'bare'; name = 'Public' })
            }
            { Get-ImperionSensitivityLabel } | Should -Not -Throw
            (@(Get-ImperionSensitivityLabel)[0]).priority | Should -BeNullOrEmpty
        }
    }

    It 'collects from the requested tenant via the per-client onboarding-app token' {
        InModuleScope ImperionPipeline {
            Get-ImperionSensitivityLabel -TenantId 'customer-9' | Out-Null
            Should -Invoke Get-ImperionGraphToken -Times 1 -ParameterFilter { $TenantId -eq 'customer-9' }
        }
    }
}
