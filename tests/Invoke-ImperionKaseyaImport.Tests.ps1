#Requires -Modules Pester
# Hermetic test for Invoke-ImperionKaseyaImport: the connect layer + DB are mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionKaseyaImport' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 't1' } }
            Mock Get-ImperionSecretNames { @{ AutotaskUserName = 'autotask-username'; AutotaskIntegrationCode = 'autotask-integration-code'; AutotaskSecret = 'autotask-secret'; KqmApiKey = 'kqm-api-key'; KqmApiKeyVaultSecret = 'KQM-API-Key' } }
            Mock Get-ImperionSecretValue { 'secret-value' }
            Mock New-ImperionDbConnection { [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { } }
            Mock Write-ImperionLog { }
        }
    }

    It 'loads Autotask contracts via the connect layer (no inline zone/paging)' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionAutotaskZone { 'https://ws.autotask.net/atservicesrest/V1.0' }
            Mock Invoke-ImperionAutotaskRequest { , @([pscustomobject]@{ id = 1; contractName = 'C1' }) }
            $tables = @{}
            Mock Invoke-ImperionBronzeUpsert { $tables[$Table] = $Rows; [pscustomobject]@{ scanned = 1; inserted = 1; updated = 0; unchanged = 0 } }

            { Invoke-ImperionKaseyaImport -Entity Contracts } | Should -Not -Throw
            Should -Invoke Get-ImperionAutotaskZone -Times 1
            Should -Invoke Invoke-ImperionAutotaskRequest -Times 1 -ParameterFilter { $Entity -eq 'Contracts' }
            $tables.ContainsKey('autotask_contracts') | Should -BeTrue
        }
    }

    It 'loads KQM proposals through the verified collector path (issue #98 delegation)' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionKeyVaultSecret { 'kv-kqm-key' }   # SecretStore not unlocked in tests -> KV original
            Mock Invoke-ImperionKqmRequest { , @([pscustomobject]@{ id = 'q1'; name = 'Quote 1'; status = 'draft' }) }
            $tables = @{}
            Mock Invoke-ImperionBronzeUpsert { $tables[$Table] = $Rows; [pscustomobject]@{ scanned = 1; inserted = 1; updated = 0; unchanged = 0 } }

            { Invoke-ImperionKaseyaImport -Entity Proposals } | Should -Not -Throw
            # The connect layer receives the key separately; the URI it is handed carries no apikey.
            Should -Invoke Invoke-ImperionKqmRequest -Times 1 -ParameterFilter { $ApiKey -eq 'kv-kqm-key' -and $Uri -notmatch 'apikey' }
            $tables.ContainsKey('kqm_proposals') | Should -BeTrue
            $tables['kqm_proposals'][0].name | Should -Be 'Quote 1'
        }
    }
}
