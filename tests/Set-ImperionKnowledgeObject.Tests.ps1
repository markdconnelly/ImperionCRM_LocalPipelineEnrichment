#Requires -Modules Pester
# Hermetic tests for Set-ImperionKnowledgeObject: DB layer mocked; tally classification.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionKnowledgeObject' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog {}
        }
    }

    It 'classifies inserted / updated / unchanged from the RETURNING shape' {
        InModuleScope ImperionPipeline {
            $script:callIndex = 0
            Mock Invoke-ImperionDbQuery {
                $script:callIndex++
                switch ($script:callIndex) {
                    1 { @([pscustomobject]@{ was_inserted = $true }) }    # new row
                    2 { @([pscustomobject]@{ was_inserted = $false }) }   # hash changed
                    3 { @() }                                             # hash identical → no row
                }
            }
            $rows = @(
                [pscustomobject]@{ tenant_id = 't'; entity_type = 'account'; entity_ref = 'a1'; title = 'A'; body = 'b'; summary = $null; source = 'local-pipeline'; metadata = '{}'; content_hash = 'h1' }
                [pscustomobject]@{ tenant_id = 't'; entity_type = 'account'; entity_ref = 'a2'; title = 'B'; body = 'b'; summary = $null; source = 'local-pipeline'; metadata = '{}'; content_hash = 'h2' }
                [pscustomobject]@{ tenant_id = 't'; entity_type = 'account'; entity_ref = 'a3'; title = 'C'; body = 'b'; summary = $null; source = 'local-pipeline'; metadata = '{}'; content_hash = 'h3' }
            )
            $tally = $rows | Set-ImperionKnowledgeObject -Connection ([pscustomobject]@{})
            $tally.scanned   | Should -Be 3
            $tally.inserted  | Should -Be 1
            $tally.updated   | Should -Be 1
            $tally.unchanged | Should -Be 1
        }
    }

    It 'returns a zero tally for empty input without touching the database' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery {}
            $tally = @() | Set-ImperionKnowledgeObject -Connection ([pscustomobject]@{})
            $tally.scanned | Should -Be 0
            Should -Invoke Invoke-ImperionDbQuery -Times 0
        }
    }

    It 'honours -WhatIf (no writes)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery {}
            $row = [pscustomobject]@{ tenant_id = 't'; entity_type = 'contact'; entity_ref = 'c1'; title = 'X'; body = 'b'; summary = $null; source = 'local-pipeline'; metadata = '{}'; content_hash = 'h' }
            $row | Set-ImperionKnowledgeObject -Connection ([pscustomobject]@{}) -WhatIf | Out-Null
            Should -Invoke Invoke-ImperionDbQuery -Times 0
        }
    }
}
