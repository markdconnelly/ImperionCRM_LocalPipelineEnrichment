#Requires -Modules Pester
# Hermetic tests for Get-ImperionITGlueContact: secrets + IT Glue request mocked.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionITGlueContact' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'partner'; ITGlue = @{ BaseUri = 'https://api.itglue.com' } } }
            Mock Get-ImperionSecretNames { @{ ITGlueReadKey = 'ITGlue-API-Key' } }
            Mock Get-ImperionSecretValue { 'key-value' }
        }
    }

    It 'flattens contact attributes and joins the contact-emails array' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionITGlueRequest {
                , @([pscustomobject]@{ id = '7'; type = 'contacts'; attributes = [pscustomobject]@{
                            name = 'Ada Lovelace'; 'first-name' = 'Ada'; 'last-name' = 'Lovelace'; 'organization-id' = 42; 'organization-name' = 'Acme'
                            'contact-emails' = @([pscustomobject]@{ value = 'ada@acme.com'; primary = $true }, [pscustomobject]@{ value = 'ada.l@acme.com' })
                        } })
            }
            $rows = Get-ImperionITGlueContact
            $rows[0].name            | Should -Be 'Ada Lovelace'
            $rows[0].organization_id | Should -Be '42'
            $rows[0].emails          | Should -Be 'ada@acme.com; ada.l@acme.com'
            $rows[0].source          | Should -Be 'itglue'
            $rows[0].external_id     | Should -Be '7'
        }
    }

    It 'does not throw when a contact has no emails' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionITGlueRequest { , @([pscustomobject]@{ id = '8'; type = 'contacts'; attributes = [pscustomobject]@{ name = 'No Email' } }) }
            { Get-ImperionITGlueContact } | Should -Not -Throw
            (Get-ImperionITGlueContact)[0].emails | Should -BeNullOrEmpty
        }
    }

    It 'requests the contacts endpoint' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionITGlueRequest { , @() }
            Get-ImperionITGlueContact | Out-Null
            Should -Invoke Invoke-ImperionITGlueRequest -Times 1 -ParameterFilter { $Path -eq 'contacts' }
        }
    }
}
