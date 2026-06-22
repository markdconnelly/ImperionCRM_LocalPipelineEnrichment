#Requires -Modules Pester
# Hermetic tests for Get-ImperionITGlueOrganization: secrets + IT Glue request mocked.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionITGlueOrganization' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'partner'; ITGlue = @{ BaseUri = 'https://api.itglue.com' } } }
            Mock Resolve-ImperionITGlueApiKey { 'key-value' }
        }
    }

    It 'flattens organization attributes to the bronze envelope' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionITGlueRequest {
                , @([pscustomobject]@{ id = '42'; type = 'organizations'; attributes = [pscustomobject]@{ name = 'Acme'; 'organization-type-name' = 'Customer'; 'primary-domain' = 'acme.com'; 'updated-at' = '2026-06-01' } })
            }
            $rows = Get-ImperionITGlueOrganization
            $rows[0].name              | Should -Be 'Acme'
            $rows[0].organization_type | Should -Be 'Customer'
            $rows[0].primary_domain    | Should -Be 'acme.com'
            $rows[0].source            | Should -Be 'itglue'
            $rows[0].external_id       | Should -Be '42'
        }
    }

    It 'does not throw when an organization omits optional attributes' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionITGlueRequest { , @([pscustomobject]@{ id = '43'; type = 'organizations'; attributes = [pscustomobject]@{ name = 'Bare' } }) }
            { Get-ImperionITGlueOrganization } | Should -Not -Throw
            (Get-ImperionITGlueOrganization)[0].primary_domain | Should -BeNullOrEmpty
        }
    }

    It 'requests the organizations endpoint with the configured base + api key' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionITGlueRequest { , @() }
            Get-ImperionITGlueOrganization | Out-Null
            Should -Invoke Invoke-ImperionITGlueRequest -Times 1 -ParameterFilter { $Path -eq 'organizations' -and $ApiKey -eq 'key-value' -and $BaseUri -eq 'https://api.itglue.com' }
        }
    }
}
