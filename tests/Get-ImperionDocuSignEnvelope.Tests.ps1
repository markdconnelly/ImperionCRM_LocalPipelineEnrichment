#Requires -Modules Pester
# Hermetic tests for Get-ImperionDocuSignEnvelope: secrets + DocuSign request mocked.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionDocuSignEnvelope' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'partner' } }
            Mock Get-ImperionSecretNames { @{ DocuSignToken = 'docusign-token'; DocuSignAccountId = 'docusign-account-id' } }
            Mock Get-ImperionSecretValue { param($Name) if ($Name -eq 'docusign-account-id') { 'acct-1' } else { 'ds-token' } }
        }
    }

    It 'flattens envelopes to the docusign_contracts bronze shape (account_ref = first signer email)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDocuSignRequest {
                , @([pscustomobject]@{
                    envelopeId = 'env-1'; emailSubject = 'MSA — Acme Corp'; status = 'completed'
                    sentDateTime = '2026-05-01T12:00:00Z'; completedDateTime = '2026-05-02T09:30:00Z'
                    recipients = [pscustomobject]@{ signers = @(
                        [pscustomobject]@{ email = 'jane@acme.com'; name = 'Jane Doe' }
                        [pscustomobject]@{ email = 'mark@imperion.com'; name = 'Mark' }
                    ) }
                })
            }
            $rows = Get-ImperionDocuSignEnvelope
            $rows.Count           | Should -Be 1
            $rows[0].external_id  | Should -Be 'env-1'
            $rows[0].subject      | Should -Be 'MSA — Acme Corp'
            $rows[0].status       | Should -Be 'completed'
            $rows[0].account_ref  | Should -Be 'jane@acme.com'
            $rows[0].sent_at      | Should -Be '2026-05-01T12:00:00Z'
            $rows[0].completed_at | Should -Be '2026-05-02T09:30:00Z'
            $rows[0].source       | Should -Be 'docusign'
            $rows[0].tenant_id    | Should -Be 'partner'
        }
    }

    It 'does not throw when an envelope has no recipients (StrictMode-safe)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDocuSignRequest { , @([pscustomobject]@{ envelopeId = 'env-2'; status = 'sent' }) }
            $rows = Get-ImperionDocuSignEnvelope
            $rows[0].account_ref | Should -BeNullOrEmpty
        }
    }

    It 'sends the token, account id, and from_date window to the connect layer' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDocuSignRequest { , @() }
            Get-ImperionDocuSignEnvelope -FromDate '2026-06-01' | Out-Null
            Should -Invoke Invoke-ImperionDocuSignRequest -Times 1 -ParameterFilter {
                $AccessToken -eq 'ds-token' -and $Uri -like '*accounts/acct-1/envelopes?from_date=2026-06-01*'
            }
        }
    }
}
