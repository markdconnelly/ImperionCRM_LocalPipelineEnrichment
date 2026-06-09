#Requires -Modules Pester
# Hermetic tests for Invoke-ImperionVectorizeKnowledge: DB + Voyage layers mocked;
# proves the change-detection (no re-embed, no re-bill) and the per-object replace.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionVectorizeKnowledge' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog {}
            Mock Get-ImperionVoyageEmbedding {
                [pscustomobject]@{
                    Embeddings  = @(1..@($Text).Count | ForEach-Object { , (@(0.25) * 1024) })
                    TotalTokens = (@($Text).Count * 10)
                    Model       = 'voyage-3-large'
                }
            }
            Mock Invoke-ImperionDbNonQuery { 1 }
        }
    }

    It 'embeds a new knowledge object and writes its chunk rows' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery {
                if ($Sql -match 'FROM knowledge_object') {
                    return @([pscustomobject]@{ id = 'ko-1'; entity_type = 'account'; title = 'Acme'; body = 'short body text' })
                }
                return @()   # no existing embeddings
            }
            $tally = Invoke-ImperionVectorizeKnowledge -Connection ([pscustomobject]@{})
            $tally.embedded | Should -Be 1
            $tally.chunks   | Should -Be 1
            $tally.tokens   | Should -Be 10
            # one DELETE + one INSERT
            Should -Invoke Invoke-ImperionDbNonQuery -Times 1 -ParameterFilter { $Sql -match 'DELETE FROM knowledge_embedding' }
            Should -Invoke Invoke-ImperionDbNonQuery -Times 1 -ParameterFilter { $Sql -match 'INSERT INTO knowledge_embedding' }
        }
    }

    It 'stamps the pinned contract on every inserted chunk row' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery {
                if ($Sql -match 'FROM knowledge_object') {
                    return @([pscustomobject]@{ id = 'ko-1'; entity_type = 'account'; title = 'Acme'; body = 'short body text' })
                }
                return @()
            }
            Invoke-ImperionVectorizeKnowledge -Connection ([pscustomobject]@{}) | Out-Null
            Should -Invoke Invoke-ImperionDbNonQuery -Times 1 -ParameterFilter {
                $Sql -match 'INSERT INTO knowledge_embedding' -and
                $Parameters.model -eq 'voyage-3-large' -and
                $Parameters.dim -eq 1024 -and
                $Parameters.version -eq 'v1' -and
                $Parameters.vec -match '^\[' -and
                $Parameters.tokens -gt 0
            }
        }
    }

    It 'skips an object whose chunk hashes are already embedded (no re-bill)' {
        InModuleScope ImperionPipeline {
            $body = 'unchanged body text'
            $chunkHash = Get-ImperionContentHash -InputObject @{ chunk_text = $body }
            Mock Invoke-ImperionDbQuery {
                if ($Sql -match 'FROM knowledge_object') {
                    return @([pscustomobject]@{ id = 'ko-1'; entity_type = 'account'; title = 'Acme'; body = 'unchanged body text' })
                }
                if ($Sql -match 'FROM knowledge_embedding') {
                    return @([pscustomobject]@{ id = 'ko-1'; chunk_index = 0; content_hash = $chunkHash })
                }
                return @()
            }
            $tally = Invoke-ImperionVectorizeKnowledge -Connection ([pscustomobject]@{})
            $tally.unchanged | Should -Be 1
            $tally.embedded  | Should -Be 0
            Should -Invoke Get-ImperionVoyageEmbedding -Times 0
            Should -Invoke Invoke-ImperionDbNonQuery -Times 0
        }
    }

    It 'honours -WhatIf (counts the work, calls neither Voyage nor the DB writers)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery {
                if ($Sql -match 'FROM knowledge_object') {
                    return @([pscustomobject]@{ id = 'ko-1'; entity_type = 'account'; title = 'Acme'; body = 'short body text' })
                }
                return @()
            }
            $tally = Invoke-ImperionVectorizeKnowledge -Connection ([pscustomobject]@{}) -WhatIf
            $tally.embedded | Should -Be 0
            $tally.chunks   | Should -Be 1
            Should -Invoke Get-ImperionVoyageEmbedding -Times 0
            Should -Invoke Invoke-ImperionDbNonQuery -Times 0
        }
    }

    It 'returns a zero tally when there are no knowledge objects' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { @() }
            $tally = Invoke-ImperionVectorizeKnowledge -Connection ([pscustomobject]@{})
            $tally.objects | Should -Be 0
            Should -Invoke Get-ImperionVoyageEmbedding -Times 0
        }
    }
}
