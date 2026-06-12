#Requires -Modules Pester
# Hermetic unit tests for the KQM live-shape probe Get-ImperionKqmFieldName.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionKqmFieldName' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionSecretNames { @{ KqmApiKey = 'kqm-api-key'; KqmApiKeyVaultSecret = 'KQM-API-Key' } }
            Mock Write-ImperionLog { }
        }
    }

    It 'emits field NAMES, types, and non-null tallies - never values' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionKqmRequest {
                @(
                    [pscustomobject]@{ id = 1; name = 'CONFIDENTIAL QUOTE'; total = 9.5; notes = $null },
                    [pscustomobject]@{ id = 2; name = 'ALSO SECRET'; total = $null; notes = 'x' }
                )
            }
            $fields = @(Get-ImperionKqmFieldName -ApiKey 'k')
            ($fields.Field -join ',') | Should -Be 'id,name,notes,total'
            ($fields | Where-Object Field -EQ 'name').Type | Should -Be 'String'
            ($fields | Where-Object Field -EQ 'total').NonNullOfSample | Should -Be 1
            ($fields | Where-Object Field -EQ 'id').SampleSize | Should -Be 2
            # The probe output must carry no record values anywhere.
            ($fields | ConvertTo-Json -Depth 5) | Should -Not -Match 'CONFIDENTIAL|ALSO SECRET'
        }
    }

    It 'probes a single page of the chosen endpoint only' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionKqmRequest { @([pscustomobject]@{ id = 1 }) }
            Get-ImperionKqmFieldName -Endpoint salesorder -ApiKey 'k' | Out-Null
            Should -Invoke Invoke-ImperionKqmRequest -Times 1 -ParameterFilter {
                $Uri -eq 'https://api.kaseyaquotemanager.com/v1/salesorder' -and $MaxPages -eq 1
            }
        }
    }

    It 'warns and returns nothing when the endpoint is empty' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionKqmRequest { @() }
            $fields = Get-ImperionKqmFieldName -ApiKey 'k'
            $fields | Should -BeNullOrEmpty
            Should -Invoke Write-ImperionLog -Times 1 -ParameterFilter { $Level -eq 'Warn' }
        }
    }
}
