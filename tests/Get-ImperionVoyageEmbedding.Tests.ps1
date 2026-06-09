#Requires -Modules Pester
# Hermetic tests for Get-ImperionVoyageEmbedding: REST layer mocked; contract enforced.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionVoyageEmbedding' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            # Fake Voyage: one correct-dimension vector per input, 7 tokens per input.
            Mock Invoke-ImperionRestWithRetry {
                $request = $Body | ConvertFrom-Json
                $data = for ($i = 0; $i -lt @($request.input).Count; $i++) {
                    [pscustomobject]@{ index = $i; embedding = @(0.5) * 1024 }
                }
                [pscustomobject]@{
                    Body = [pscustomobject]@{
                        data  = @($data)
                        usage = [pscustomobject]@{ total_tokens = (@($request.input).Count * 7) }
                    }
                    Status = 200; Headers = @{}
                }
            }
        }
    }

    It 'sends the pinned model, dimension, and input_type' {
        InModuleScope ImperionPipeline {
            Get-ImperionVoyageEmbedding -Text @('hello') -InputType document -ApiKey 'k' | Out-Null
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter {
                $request = $Body | ConvertFrom-Json
                $request.model -eq 'voyage-3-large' -and
                $request.output_dimension -eq 1024 -and
                $request.input_type -eq 'document' -and
                $Headers.Authorization -eq 'Bearer k'
            }
        }
    }

    It 'returns one embedding per input, in order, with the billed token total' {
        InModuleScope ImperionPipeline {
            $result = Get-ImperionVoyageEmbedding -Text @('one', 'two', 'three') -ApiKey 'k'
            @($result.Embeddings).Count       | Should -Be 3
            @($result.Embeddings[0]).Count    | Should -Be 1024
            $result.TotalTokens               | Should -Be 21
            $result.Model                     | Should -Be 'voyage-3-large'
        }
    }

    It 'batches inputs beyond the API batch size into multiple calls' {
        InModuleScope ImperionPipeline {
            $many = @(1..130 | ForEach-Object { "text $_" })
            $result = Get-ImperionVoyageEmbedding -Text $many -ApiKey 'k'
            @($result.Embeddings).Count | Should -Be 130
            Should -Invoke Invoke-ImperionRestWithRetry -Times 3   # 64 + 64 + 2
        }
    }

    It 'refuses a wrong-dimension vector (vector spaces never mix)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                [pscustomobject]@{
                    Body = [pscustomobject]@{
                        data  = @([pscustomobject]@{ index = 0; embedding = @(0.5) * 1536 })
                        usage = [pscustomobject]@{ total_tokens = 5 }
                    }
                    Status = 200; Headers = @{}
                }
            }
            { Get-ImperionVoyageEmbedding -Text @('x') -ApiKey 'k' } | Should -Throw '*pinned contract*'
        }
    }

    It 'resolves the API key from the SecretStore when not passed' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionSecretNames { @{ EmbeddingProviderKey = 'embedding-provider-key' } }
            Mock Get-ImperionSecretValue { 'vault-key' } -ParameterFilter { $Name -eq 'embedding-provider-key' }
            Get-ImperionVoyageEmbedding -Text @('x') | Out-Null
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter {
                $Headers.Authorization -eq 'Bearer vault-key'
            }
        }
    }
}
