#Requires -Modules Pester
# Hermetic unit tests for Invoke-ImperionM365DirectoryMerge: ShouldProcess gating and the
# idempotency / provenance contracts pinned in the merge SQL (issue #239; the on-prem twin
# of the cloud Pipeline's mergeDirectoryGroups, front-end migration 0079).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionM365DirectoryMerge' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection {
                [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            }
        }
    }

    It 'honors -WhatIf: no connection, no SQL' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbNonQuery { 0 }
            Invoke-ImperionM365DirectoryMerge -WhatIf | Out-Null
            Should -Invoke Invoke-ImperionDbNonQuery -Times 0
            Should -Invoke New-ImperionDbConnection -Times 0
        }
    }

    Context 'merge SQL contracts' {
        BeforeEach {
            InModuleScope ImperionPipeline {
                $script:capturedSql = [System.Collections.Generic.List[string]]::new()
                Mock Invoke-ImperionDbNonQuery { $script:capturedSql.Add($Sql); 3 }
            }
        }

        It 'runs exactly two steps (clear then insert) and returns the tally' {
            InModuleScope ImperionPipeline {
                $tally = Invoke-ImperionM365DirectoryMerge -Confirm:$false
                $script:capturedSql.Count | Should -Be 2
                $tally.stale_cleared | Should -Be 3
                $tally.contacts_enriched | Should -Be 3
                Should -Invoke Write-ImperionLog -Times 1 -ParameterFilter { $Level -eq 'Metric' -and $Message -match 'Merge plan complete \(m365\)' }
            }
        }

        It 'step 1 clears only this source''s prior facts (replace-from-source idempotency)' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionM365DirectoryMerge -Confirm:$false | Out-Null
                $deleteSql = @($script:capturedSql | Where-Object { $_ -match 'DELETE FROM contact_enrichment' })[0]
                $deleteSql | Should -Not -BeNullOrEmpty
                $deleteSql | Should -Match "WHERE source = 'm365_directory'"
            }
        }

        It 'step 2 stamps the directory_groups fact through the provenance guardrail' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionM365DirectoryMerge -Confirm:$false | Out-Null
                $insertSql = @($script:capturedSql | Where-Object { $_ -match 'INSERT INTO contact_enrichment' })[0]
                $insertSql | Should -Not -BeNullOrEmpty
                $insertSql | Should -Match "'directory_groups'"
                $insertSql | Should -Match "'m365_directory'"
                $insertSql | Should -Match "'legitimate_interest'::lawful_basis"
            }
        }

        It 'step 2 pins the 0079 join contract (member_external_id = external_ref; groups by tenant+external_id)' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionM365DirectoryMerge -Confirm:$false | Out-Null
                $insertSql = @($script:capturedSql | Where-Object { $_ -match 'INSERT INTO contact_enrichment' })[0]
                $insertSql | Should -Match 'JOIN m365_group_members gm'
                $insertSql | Should -Match 'gm\.member_external_id = c\.external_ref'
                $insertSql | Should -Match '(?s)LEFT JOIN m365_groups g.*g\.tenant_id   = gm\.tenant_id.*g\.external_id = gm\.group_external_id'
                $insertSql | Should -Match 'GROUP BY c\.contact_id'
            }
        }

        It 'step 2 only emits a fact for contacts WITH membership (HAVING guard)' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionM365DirectoryMerge -Confirm:$false | Out-Null
                $insertSql = @($script:capturedSql | Where-Object { $_ -match 'INSERT INTO contact_enrichment' })[0]
                $insertSql | Should -Match 'HAVING count\(gm\.group_external_id\) FILTER \(WHERE gm\.group_external_id IS NOT NULL\) > 0'
            }
        }

        It 'step 2 regex-guards the bronze text collected_at before casting (junk -> now(), never throws)' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionM365DirectoryMerge -Confirm:$false | Out-Null
                $insertSql = @($script:capturedSql | Where-Object { $_ -match 'INSERT INTO contact_enrichment' })[0]
                $insertSql | Should -Match ([regex]::Escape("CASE WHEN max(gm.collected_at) ~ '^\d{4}-\d{2}-\d{2}' THEN max(gm.collected_at)::timestamptz"))
            }
        }

        It 'reuses a passed connection without disposing it' {
            InModuleScope ImperionPipeline {
                $disposed = @{ v = $false }
                $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { $disposed.v = $true }.GetNewClosure()
                Invoke-ImperionM365DirectoryMerge -Connection $conn -Confirm:$false | Out-Null
                Should -Invoke New-ImperionDbConnection -Times 0
                $disposed.v | Should -BeFalse
            }
        }
    }
}
