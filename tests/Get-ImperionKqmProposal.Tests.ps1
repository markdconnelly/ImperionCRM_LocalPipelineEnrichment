#Requires -Modules Pester
# Hermetic unit tests for Get-ImperionKqmProposal. Connect layer + context mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionKqmProposal' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'partner-tenant' } }
            Mock Get-ImperionSecretNames { @{ KqmApiKey = 'kqm-api-key'; KqmApiKeyVaultSecret = 'KQM-API-Key' } }
            Mock Write-ImperionLog { }
        }
    }

    It 'flattens a quote to the kqm_proposals shape with the standard envelope' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionKqmRequest {
                , @([pscustomobject]@{ id = 77; name = 'Onboarding bundle'; status = 'won'; total = 1234.5; customerName = 'Acme'; createdDate = '2026-05-01'; modifiedDate = '2026-06-01' })
            }
            $rows = @(Get-ImperionKqmProposal -ApiKey 'k')
            $rows.Count | Should -Be 1
            $rows[0].name | Should -Be 'Onboarding bundle'
            $rows[0].status | Should -Be 'won'
            $rows[0].total | Should -Be '1234.5'
            $rows[0].account_ref | Should -Be 'Acme'
            $rows[0].source | Should -Be 'kqm'
            $rows[0].tenant_id | Should -Be 'partner-tenant'
            $rows[0].external_id | Should -Be '77'
            $rows[0].content_hash | Should -Not -BeNullOrEmpty
            $rows[0].raw_payload | Should -Match 'Onboarding bundle'
        }
    }

    It 'survives unknown field names: flat columns land null, raw_payload keeps everything' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionKqmRequest { , @([pscustomobject]@{ id = 9; surpriseField = 'x' }) }
            $rows = @(Get-ImperionKqmProposal -ApiKey 'k')
            $rows[0].name | Should -BeNullOrEmpty
            $rows[0].external_id | Should -Be '9'
            $rows[0].raw_payload | Should -Match 'surpriseField'
        }
    }

    It 'passes the modifiedAfter filter and never puts the key in the URI it builds' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionKqmRequest { @() }
            Get-ImperionKqmProposal -ApiKey 'sekret' -ModifiedAfter '2026-06-01T00:00:00Z' | Out-Null
            Should -Invoke Invoke-ImperionKqmRequest -Times 1 -ParameterFilter {
                $Uri -match 'modifiedAfter=2026-06-01T00%3A00%3A00Z' -and $Uri -notmatch 'sekret' -and $ApiKey -eq 'sekret'
            }
        }
    }

    It 'falls back to the Key Vault original when no explicit key and the SecretStore is locked' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionKeyVaultSecret { 'kv-value' }
            Mock Invoke-ImperionKqmRequest { @() }
            Get-ImperionKqmProposal | Out-Null
            Should -Invoke Get-ImperionKeyVaultSecret -Times 1 -ParameterFilter { $Name -eq 'KQM-API-Key' }
            Should -Invoke Invoke-ImperionKqmRequest -Times 1 -ParameterFilter { $ApiKey -eq 'kv-value' }
        }
    }
}
