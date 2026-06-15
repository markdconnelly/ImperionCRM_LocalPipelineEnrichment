#Requires -Modules Pester
# Hermetic test for Get-ImperionDnsDrift (issue #157): the DB read is mocked in module
# scope; we assert the classification + verdict contract is present in the SQL it issues
# and that it passes rows straight through.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionDnsDrift' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock New-ImperionDbConnection { [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { } }
            Mock Write-ImperionLog { }
        }
    }

    It 'classifies records with the four-state golden/drift CASE (parity with policy drift)' {
        InModuleScope ImperionPipeline {
            $script:capturedSql = $null
            Mock Invoke-ImperionDbQuery { $script:capturedSql = $Sql; @() }

            Get-ImperionDnsDrift | Out-Null

            $script:capturedSql | Should -Match "WHEN g\.name IS NULL THEN 'ungoverned'"
            $script:capturedSql | Should -Match "WHEN c\.name IS NULL THEN 'missing'"
            $script:capturedSql | Should -Match "WHEN c\.content_hash = g\.content_hash THEN 'compliant'"
            $script:capturedSql | Should -Match "ELSE 'drift'"
            $script:capturedSql | Should -Match 'FULL OUTER JOIN'
        }
    }

    It 'reconciles the three-state governance verdict across both planes (ADR-0063)' {
        InModuleScope ImperionPipeline {
            $script:capturedSql = $null
            Mock Invoke-ImperionDbQuery { $script:capturedSql = $Sql; @() }

            Get-ImperionDnsDrift | Out-Null

            # not-in-azure when no zone; managed only when in-azure AND manageable AND NS delegated.
            $script:capturedSql | Should -Match "WHEN az\.in_azure IS NOT TRUE THEN 'not-in-azure'"
            $script:capturedSql | Should -Match "az\.manageable IS TRUE AND nd\.domain IS NOT NULL THEN 'managed'"
            $script:capturedSql | Should -Match "ELSE 'in-azure-readonly'"
            # cross-plane NS-delegation reconciliation present
            $script:capturedSql | Should -Match 'ns_delegated'
            $script:capturedSql | Should -Match "record_type = 'NS'"
            # the public plane is the captured ground truth
            $script:capturedSql | Should -Match "r\.plane = 'public'"
            # domain set of record is account_domain
            $script:capturedSql | Should -Match 'FROM account_domain'
        }
    }

    It 'filters to a single domain when -Domain is supplied' {
        InModuleScope ImperionPipeline {
            $script:capturedSql = $null
            Mock Invoke-ImperionDbQuery { $script:capturedSql = $Sql; @() }

            Get-ImperionDnsDrift -Domain 'contoso.com' | Out-Null

            Should -Invoke Invoke-ImperionDbQuery -Times 1 -ParameterFilter {
                $Sql -match 'WHERE ad\.domain = @domain' -and $Parameters.domain -eq 'contoso.com'
            }
        }
    }

    It 'returns the rows it reads unchanged' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery {
                @([pscustomobject]@{ domain = 'contoso.com'; verdict = 'managed'; records_compliant = 6 })
            }
            $rows = @(Get-ImperionDnsDrift)
            $rows.Count | Should -Be 1
            $rows[0].verdict | Should -Be 'managed'
        }
    }
}
