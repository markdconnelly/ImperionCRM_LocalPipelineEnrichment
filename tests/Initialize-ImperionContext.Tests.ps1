#Requires -Modules Pester
# Hermetic tests for Initialize-ImperionContext: config load + SecretStore unlock are mocked.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Initialize-ImperionContext' {
    AfterEach {
        # Undo module-state side effects so other test files start clean.
        InModuleScope ImperionPipeline { $script:ImperionLogDirectory = $null; $script:ImperionNpgsqlPath = $null; $script:ImperionConfig = $null }
        Remove-Item Env:\IMPERION_LOG_DIR, Env:\IMPERION_NPGSQL_DLL -ErrorAction SilentlyContinue
    }

    It 'loads config, sets runtime paths, and unlocks the SecretStore' {
        InModuleScope ImperionPipeline {
            Mock Test-Path { $true }
            Mock Import-PowerShellDataFile { @{ LocalTenantId = 't1'; LogDirectory = 'C:\logs\imperion'; NpgsqlDllPath = 'C:\lib\Npgsql.dll'; CmsPasswordPath = 'C:\v.cms'; SecretVault = 'ImperionStore' } }
            Mock Connect-ImperionSecretStore { }
            Mock Write-ImperionLog { }

            Initialize-ImperionContext -ConfigPath 'C:\ProgramData\Imperion\pipeline.config.psd1'

            $script:ImperionConfig.LocalTenantId | Should -Be 't1'
            $script:ImperionLogDirectory | Should -Be 'C:\logs\imperion'
            $env:IMPERION_NPGSQL_DLL | Should -Be 'C:\lib\Npgsql.dll'
            Should -Invoke Connect-ImperionSecretStore -Times 1 -ParameterFilter { $Authentication -eq 'Password' -and $CmsPasswordPath -eq 'C:\v.cms' -and $VaultName -eq 'ImperionStore' }
        }
    }

    It 'routes to DPAPI (Authentication None) when configured, with no CMS path' {
        InModuleScope ImperionPipeline {
            Mock Test-Path { $true }
            # Note: no CmsPasswordPath key — a DPAPI config omits it; the read must be StrictMode-safe.
            Mock Import-PowerShellDataFile { @{ LocalTenantId = 't1'; LogDirectory = 'C:\logs\imperion'; NpgsqlDllPath = 'C:\lib\Npgsql.dll'; SecretVault = 'ImperionStore'; SecretStoreAuthentication = 'None' } }
            Mock Connect-ImperionSecretStore { }
            Mock Write-ImperionLog { }

            Initialize-ImperionContext -ConfigPath 'C:\ProgramData\Imperion\pipeline.config.psd1'

            Should -Invoke Connect-ImperionSecretStore -Times 1 -ParameterFilter { $Authentication -eq 'None' -and $VaultName -eq 'ImperionStore' }
        }
    }

    It 'falls back to the legacy PartnerTenantId key when LocalTenantId is absent (#329, host-safe)' {
        InModuleScope ImperionPipeline {
            Mock Test-Path { $true }
            # An un-migrated host config still keyed the old way.
            Mock Import-PowerShellDataFile { @{ PartnerTenantId = 'legacy-tid'; LogDirectory = 'C:\logs\imperion'; NpgsqlDllPath = 'C:\lib\Npgsql.dll'; SecretVault = 'ImperionStore'; SecretStoreAuthentication = 'None' } }
            Mock Connect-ImperionSecretStore { }
            Mock Write-ImperionLog { }

            Initialize-ImperionContext -ConfigPath 'C:\ProgramData\Imperion\pipeline.config.psd1'

            $script:ImperionConfig.LocalTenantId | Should -Be 'legacy-tid'
            Should -Invoke Write-ImperionLog -ParameterFilter { $Level -eq 'Warn' -and $Message -like '*PartnerTenantId*deprecated*' }
        }
    }

    It 'prefers LocalTenantId over a stale legacy PartnerTenantId when both are present (#329)' {
        InModuleScope ImperionPipeline {
            Mock Test-Path { $true }
            Mock Import-PowerShellDataFile { @{ LocalTenantId = 'new-tid'; PartnerTenantId = 'legacy-tid'; LogDirectory = 'C:\logs\imperion'; NpgsqlDllPath = 'C:\lib\Npgsql.dll'; SecretVault = 'ImperionStore'; SecretStoreAuthentication = 'None' } }
            Mock Connect-ImperionSecretStore { }
            Mock Write-ImperionLog { }

            Initialize-ImperionContext -ConfigPath 'C:\ProgramData\Imperion\pipeline.config.psd1'

            $script:ImperionConfig.LocalTenantId | Should -Be 'new-tid'
            Should -Not -Invoke Write-ImperionLog -ParameterFilter { $Message -like '*PartnerTenantId*deprecated*' }
        }
    }

    It 'throws an actionable error when the config file is missing' {
        InModuleScope ImperionPipeline {
            Mock Test-Path { $false }
            { Initialize-ImperionContext -ConfigPath 'C:\nope\pipeline.config.psd1' } | Should -Throw '*Config not found*'
        }
    }
}
