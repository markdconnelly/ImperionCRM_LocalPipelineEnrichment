#Requires -Modules Pester
# Hermetic unit tests for Get-ImperionQboProfitAndLoss. Calls the Reports API (not the query
# helper), so the transport/retry core Invoke-ImperionRestWithRetry is mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionQboProfitAndLoss' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'partner-tenant' } }
            Mock Get-ImperionSecretNames { @{ QboAccessToken = 'qbo-access-token'; QboRealmId = 'qbo-realm-id' } }
            Mock Get-ImperionSecretValue { if ($Name -eq 'qbo-access-token') { 'tok-123' } else { 'realm-999' } }
            Mock Write-ImperionLog { }
        }
    }

    It 'flattens a P&L report into one snapshot row keyed on the period, pulling the headline totals' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                [pscustomobject]@{ Status = 200; Headers = @{}; Body = [pscustomobject]@{
                        Header = [pscustomobject]@{ ReportName = 'ProfitAndLoss'; Currency = 'USD'; Time = '2026-06-15T12:00:00-00:00' }
                        Rows = [pscustomobject]@{ Row = @(
                                [pscustomobject]@{ Summary = [pscustomobject]@{ ColData = @([pscustomobject]@{ value = 'Total Income' }, [pscustomobject]@{ value = '20000.00' }) } }
                                [pscustomobject]@{ Summary = [pscustomobject]@{ ColData = @([pscustomobject]@{ value = 'Total Expenses' }, [pscustomobject]@{ value = '12000.00' }) } }
                                [pscustomobject]@{ Summary = [pscustomobject]@{ ColData = @([pscustomobject]@{ value = 'Net Income' }, [pscustomobject]@{ value = '8000.00' }) } }
                            ) }
                    } }
            }
            $rows = @(Get-ImperionQboProfitAndLoss -StartDate '2026-06-01' -EndDate '2026-06-30')
            $rows.Count | Should -Be 1
            $rows[0].period | Should -Be '2026-06-01..2026-06-30'
            $rows[0].start_date | Should -Be '2026-06-01'
            $rows[0].end_date | Should -Be '2026-06-30'
            $rows[0].currency | Should -Be 'USD'
            $rows[0].total_income | Should -Be '20000.00'
            $rows[0].total_expenses | Should -Be '12000.00'
            $rows[0].net_income | Should -Be '8000.00'
            $rows[0].external_id | Should -Be '2026-06-01..2026-06-30'
            $rows[0].source | Should -Be 'qbo'
            $rows[0].content_hash | Should -Not -BeNullOrEmpty
        }
    }

    It 'calls the ProfitAndLoss Reports endpoint with the realm and the date range' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                [pscustomobject]@{ Status = 200; Headers = @{}; Body = [pscustomobject]@{ Header = [pscustomobject]@{ ReportName = 'ProfitAndLoss' }; Rows = [pscustomobject]@{ Row = @() } } }
            }
            Get-ImperionQboProfitAndLoss -StartDate '2026-06-01' -EndDate '2026-06-30' | Out-Null
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter {
                $Uri -match 'reports/ProfitAndLoss' -and $Uri -match 'realm-999' -and
                $Uri -match 'start_date=2026-06-01' -and $Uri -match 'end_date=2026-06-30'
            }
        }
    }

    It 'survives a report with no summary rows: totals land null, raw_payload keeps the report' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                [pscustomobject]@{ Status = 200; Headers = @{}; Body = [pscustomobject]@{ Header = [pscustomobject]@{ ReportName = 'ProfitAndLoss' }; surpriseField = 'x' } }
            }
            $rows = @(Get-ImperionQboProfitAndLoss -StartDate '2026-06-01' -EndDate '2026-06-30')
            $rows[0].total_income | Should -BeNullOrEmpty
            $rows[0].net_income | Should -BeNullOrEmpty
            $rows[0].raw_payload | Should -Match 'surpriseField'
        }
    }
}
