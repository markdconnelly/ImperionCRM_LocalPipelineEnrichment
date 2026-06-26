#Requires -Modules Pester
# Hermetic unit tests for Invoke-ImperionMetaLeadAdsMerge: ShouldProcess gating and the
# idempotency contracts pinned in the merge SQL (LP #362 / front-end migration 0206).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionMetaLeadAdsMerge' {
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
            Invoke-ImperionMetaLeadAdsMerge -WhatIf | Out-Null
            Should -Invoke Invoke-ImperionDbNonQuery -Times 0
            Should -Invoke New-ImperionDbConnection -Times 0
        }
    }

    Context 'merge SQL contracts' {
        BeforeEach {
            InModuleScope ImperionPipeline {
                $script:capturedMergeSql = [System.Collections.Generic.List[string]]::new()
                Mock Invoke-ImperionDbNonQuery { $script:capturedMergeSql.Add($Sql); 1 }
            }
        }

        It 'runs all three steps and returns the tally' {
            InModuleScope ImperionPipeline {
                $tally = Invoke-ImperionMetaLeadAdsMerge -Confirm:$false
                $script:capturedMergeSql.Count | Should -Be 3
                $tally.lead_hook_ensured | Should -Be 1
                $tally.contacts_created | Should -Be 1
                $tally.lead_captures_created | Should -Be 1
                Should -Invoke Write-ImperionLog -Times 1 -ParameterFilter { $Level -eq 'Metric' -and $Message -match 'Meta Lead Ads merge complete' }
            }
        }

        It 'ensures exactly ONE facebook_lead hook stamping source=meta_lead_ad' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionMetaLeadAdsMerge -Confirm:$false | Out-Null
                $hookSql = @($script:capturedMergeSql | Where-Object { $_ -match 'INSERT INTO lead_hook' })[0]
                $hookSql | Should -Match "'facebook_lead'::lead_hook_kind"
                $hookSql | Should -Match "'Facebook Lead Ads'"
                $hookSql | Should -Match "'source', 'meta_lead_ad'"
                $hookSql | Should -Match "(?s)NOT EXISTS \(SELECT 1 FROM lead_hook\s+WHERE kind = 'facebook_lead' AND name = 'Facebook Lead Ads'\)"
            }
        }

        It 'mints one contact per distinct submitter (email-or-leadgen identity), skipping known identities' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionMetaLeadAdsMerge -Confirm:$false | Out-Null
                $contactSql = @($script:capturedMergeSql | Where-Object { $_ -match 'INSERT INTO contact ' })[0]
                $contactSql | Should -Match 'DISTINCT ON \(identity_key\)'
                $contactSql | Should -Match "COALESCE\(NULLIF\(lower\(email\), ''\), 'leadgen:' \|\| external_id\)"
                $contactSql | Should -Match "(?s)NOT EXISTS \(SELECT 1 FROM contact_social_identity csi\s+WHERE csi\.platform = 'facebook' AND csi\.external_id = s\.identity_key\)"
                $contactSql | Should -Match 'INSERT INTO contact_social_identity'
            }
        }

        It 'writes ONE lead_capture_event per lead, idempotent on the leadgen id' {
            InModuleScope ImperionPipeline {
                Invoke-ImperionMetaLeadAdsMerge -Confirm:$false | Out-Null
                $captureSql = @($script:capturedMergeSql | Where-Object { $_ -match 'INSERT INTO lead_capture_event' })[0]
                # keyed on (hook, payload leadgen_id) — the #424 idempotency contract
                $captureSql | Should -Match "e\.payload_bronze->>'leadgen_id' = l\.leadgen_id"
                $captureSql | Should -Match "'source', 'meta_lead_ad'"
                $captureSql | Should -Match "'leadgen_id', l\.leadgen_id"
                # guarded created_time cast — junk lands now(), never throws
                $captureSql | Should -Match ([regex]::Escape("CASE WHEN l.created_time ~ '^\d{4}-\d{2}-\d{2}'"))
            }
        }

        It 'reuses a passed connection without disposing it' {
            InModuleScope ImperionPipeline {
                $disposed = @{ v = $false }
                $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { $disposed.v = $true }.GetNewClosure()
                Invoke-ImperionMetaLeadAdsMerge -Connection $conn -Confirm:$false | Out-Null
                Should -Invoke New-ImperionDbConnection -Times 0
                $disposed.v | Should -BeFalse
            }
        }
    }
}
