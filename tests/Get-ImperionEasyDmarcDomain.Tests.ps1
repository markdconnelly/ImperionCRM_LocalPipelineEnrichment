#Requires -Modules Pester
# Hermetic tests for Get-ImperionEasyDmarcDomain: EasyDMARC request + key resolver mocked.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionEasyDmarcDomain' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'partner' } }
            Mock Resolve-ImperionEasyDmarcApiKey { 'resolved-key' }
        }
    }

    It 'flattens domains to the bronze envelope (source easydmarc), external_id = domain' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionEasyDmarcRequest {
                , @([pscustomobject]@{
                        name         = 'acme.com'
                        organization_id = 'org-1'
                        setup_status = 'verified'
                        dmarc_policy = 'reject'
                        dmarc_status = 'pass'
                        spf_status   = 'pass'
                        dkim_status  = 'pass'
                        bimi_status  = 'none'
                    })
            }
            $rows = Get-ImperionEasyDmarcDomain
            $rows[0].domain           | Should -Be 'acme.com'
            $rows[0].dmarc_policy     | Should -Be 'reject'
            $rows[0].organization_ref | Should -Be 'org-1'
            $rows[0].source           | Should -Be 'easydmarc'
            $rows[0].external_id      | Should -Be 'acme.com'
        }
    }

    It 'tolerates casing/snake-case drift on the source field names' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionEasyDmarcRequest {
                , @([pscustomobject]@{ domain = 'beta.io'; dmarcPolicy = 'quarantine'; spfStatus = 'fail' })
            }
            $rows = Get-ImperionEasyDmarcDomain
            $rows[0].domain       | Should -Be 'beta.io'
            $rows[0].dmarc_policy | Should -Be 'quarantine'
            $rows[0].spf_status   | Should -Be 'fail'
        }
    }

    It 'does not throw when posture fields are absent (StrictMode-safe)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionEasyDmarcRequest { , @([pscustomobject]@{ name = 'bare.net' }) }
            { Get-ImperionEasyDmarcDomain } | Should -Not -Throw
            (Get-ImperionEasyDmarcDomain)[0].dmarc_status | Should -BeNullOrEmpty
        }
    }

    It 'resolves the company API key via Resolve-ImperionEasyDmarcApiKey' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionEasyDmarcRequest { , @() }
            Get-ImperionEasyDmarcDomain | Out-Null
            Should -Invoke Resolve-ImperionEasyDmarcApiKey -Times 1
            Should -Invoke Invoke-ImperionEasyDmarcRequest -Times 1 -ParameterFilter { $ApiKey -eq 'resolved-key' }
        }
    }
}
