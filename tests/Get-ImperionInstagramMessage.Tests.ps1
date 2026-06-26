#Requires -Modules Pester
# Hermetic unit tests for Get-ImperionInstagramMessage (LocalPipeline #361). Connect layer +
# context mocked in module scope. IG DMs ride the linked-Page inbox with platform=instagram.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionInstagramMessage' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'partner-tenant' } }
            Mock Write-ImperionLog { }
        }
    }

    It 'emits one row per MESSAGE with conversation/ig-user stamps and the instagram_messages shape' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionMetaPageToken { 'page-token' }
            # First call resolves the IG business account; second returns the conversations.
            Mock Invoke-ImperionMetaRequest {
                if ($Uri -match 'instagram_business_account') {
                    return @([pscustomobject]@{ instagram_business_account = [pscustomobject]@{ id = 'ig99' } })
                }
                @([pscustomobject]@{
                        id       = 'conv1'
                        messages = [pscustomobject]@{ data = @(
                                [pscustomobject]@{
                                    id           = 'm1'
                                    message      = 'Hi, interested in services'
                                    from         = [pscustomobject]@{ id = 'iguser9'; username = 'jane.lead' }
                                    to           = [pscustomobject]@{ data = @([pscustomobject]@{ id = 'ig99'; username = 'imperion' }) }
                                    created_time = '2026-06-05T10:00:00+0000'
                                },
                                [pscustomobject]@{
                                    id           = 'm2'
                                    message      = 'Thanks, here is info'
                                    from         = [pscustomobject]@{ id = 'ig99'; username = 'imperion' }
                                    to           = [pscustomobject]@{ data = @(
                                            [pscustomobject]@{ id = 'ig99'; username = 'imperion' },
                                            [pscustomobject]@{ id = 'iguser9'; username = 'jane.lead' }) }
                                    created_time = '2026-06-05T10:05:00+0000'
                                })
                        }
                    })
            }
            $rows = @(Get-ImperionInstagramMessage -PageId 'page1' -PageToken 'pt')
            $rows.Count | Should -Be 2

            $rows[0].external_id | Should -Be 'm1'
            $rows[0].conversation_id | Should -Be 'conv1'
            $rows[0].ig_user_id | Should -Be 'ig99'
            $rows[0].from_id | Should -Be 'iguser9'
            $rows[0].from_username | Should -Be 'jane.lead'
            # only recipient is the IG account itself -> falls back to the first recipient
            $rows[0].to_id | Should -Be 'ig99'
            $rows[0].source | Should -Be 'instagram'

            # to_* = the first NON-account recipient when one exists
            $rows[1].from_id | Should -Be 'ig99'
            $rows[1].to_id | Should -Be 'iguser9'
            $rows[1].to_username | Should -Be 'jane.lead'

            # the conversations call used the PAGE token + the instagram platform routing
            Should -Invoke Invoke-ImperionMetaRequest -Times 1 -ParameterFilter {
                $Token -eq 'pt' -and $Uri -match '^page1/conversations\?platform=instagram&fields='
            }
        }
    }

    It 'skips the IG-user hop when -IgUserId is supplied' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionMetaRequest {
                $Uri | Should -Not -Match 'instagram_business_account'
                @()
            }
            Get-ImperionInstagramMessage -PageId 'page1' -PageToken 'pt' -IgUserId 'ig99' | Out-Null
            Should -Invoke Invoke-ImperionMetaRequest -Times 1
        }
    }

    It 'warns and returns nothing when the Page has no linked IG account' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionMetaRequest { @([pscustomobject]@{ }) }   # no instagram_business_account
            $rows = @(Get-ImperionInstagramMessage -PageId 'page1' -PageToken 'pt')
            $rows.Count | Should -Be 0
            Should -Invoke Write-ImperionLog -Times 1 -ParameterFilter { $Level -eq 'Warn' -and $Message -match 'no linked instagram_business_account' }
        }
    }

    It 'resolves the page token via Get-ImperionMetaPageToken when not supplied' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionMetaPageToken { 'page-token' }
            Mock Invoke-ImperionMetaRequest { @() }
            Get-ImperionInstagramMessage -PageId 'page1' -Token 'sys' | Out-Null
            Should -Invoke Get-ImperionMetaPageToken -Times 1 -ParameterFilter { $PageId -eq 'page1' }
        }
    }
}
