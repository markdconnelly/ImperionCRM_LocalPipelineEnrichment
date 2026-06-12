#Requires -Modules Pester
# Hermetic unit tests for Invoke-ImperionDocuSignRequest. HTTP core mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionDocuSignRequest' {
    It 'sends a bearer token and returns the envelopes collection' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                [pscustomobject]@{ Body = [pscustomobject]@{ envelopes = @([pscustomobject]@{ envelopeId = 'e1' }, [pscustomobject]@{ envelopeId = 'e2' }) } }
            }
            $rows = Invoke-ImperionDocuSignRequest -AccessToken 'tok' -Uri 'https://na4.docusign.net/restapi/v2.1/accounts/a1/envelopes?from_date=2000-01-01'
            $rows.Count | Should -Be 2
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter { $Headers.Authorization -eq 'Bearer tok' }
        }
    }

    It 'follows nextUri across pages, resolving the RELATIVE path against the base' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                if ($Uri -match 'start_position=100') {
                    [pscustomobject]@{ Body = [pscustomobject]@{ envelopes = @([pscustomobject]@{ envelopeId = 'e9' }) } }
                }
                else {
                    [pscustomobject]@{ Body = [pscustomobject]@{
                        envelopes = @([pscustomobject]@{ envelopeId = 'e1' })
                        nextUri   = '/accounts/a1/envelopes?from_date=2000-01-01&start_position=100'
                    } }
                }
            }
            $rows = Invoke-ImperionDocuSignRequest -AccessToken 't' -Uri 'https://na4.docusign.net/restapi/v2.1/accounts/a1/envelopes?from_date=2000-01-01'
            ($rows.envelopeId -join ',') | Should -Be 'e1,e9'
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter {
                $Uri -eq 'https://na4.docusign.net/restapi/v2.1/accounts/a1/envelopes?from_date=2000-01-01&start_position=100'
            }
        }
    }

    It 'does not throw when neither envelopes nor nextUri is present (StrictMode-safe)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry { [pscustomobject]@{ Body = [pscustomobject]@{ envelopeId = 'solo' } } }
            $rows = Invoke-ImperionDocuSignRequest -AccessToken 't' -Uri 'https://na4.docusign.net/restapi/v2.1/accounts/a1/envelopes/solo'
            $rows[0].envelopeId | Should -Be 'solo'
        }
    }
}
