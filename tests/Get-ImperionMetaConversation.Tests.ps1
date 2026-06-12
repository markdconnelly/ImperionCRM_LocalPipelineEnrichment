#Requires -Modules Pester
# Hermetic unit tests for Get-ImperionMetaConversation. Connect layer + context mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionMetaConversation' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'partner-tenant' } }
            Mock Write-ImperionLog { }
        }
    }

    It 'emits one row per MESSAGE with conversation/page stamps and the facebook_messages shape' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionMetaPageToken { 'page-token' }
            Mock Invoke-ImperionMetaRequest {
                @([pscustomobject]@{
                        id       = 'conv1'
                        messages = [pscustomobject]@{ data = @(
                                [pscustomobject]@{
                                    id           = 'm1'
                                    message      = 'Hi, interested in services'
                                    from         = [pscustomobject]@{ id = 'user9'; name = 'Jane Lead' }
                                    to           = [pscustomobject]@{ data = @([pscustomobject]@{ id = 'page1'; name = 'Imperion' }) }
                                    created_time = '2026-06-05T10:00:00+0000'
                                },
                                [pscustomobject]@{
                                    id           = 'm2'
                                    message      = 'Thanks, here is info'
                                    from         = [pscustomobject]@{ id = 'page1'; name = 'Imperion' }
                                    to           = [pscustomobject]@{ data = @(
                                            [pscustomobject]@{ id = 'page1'; name = 'Imperion' },
                                            [pscustomobject]@{ id = 'user9'; name = 'Jane Lead' }) }
                                    created_time = '2026-06-05T10:05:00+0000'
                                })
                        }
                    })
            }
            $rows = @(Get-ImperionMetaConversation -PageId 'page1' -Token 't')
            $rows.Count | Should -Be 2

            $rows[0].external_id | Should -Be 'm1'
            $rows[0].conversation_id | Should -Be 'conv1'
            $rows[0].page_id | Should -Be 'page1'
            $rows[0].from_id | Should -Be 'user9'
            # only recipient is the page itself -> falls back to the first recipient
            $rows[0].to_id | Should -Be 'page1'
            $rows[0].source | Should -Be 'facebook'

            # to_* = the first NON-page recipient when one exists
            $rows[1].from_id | Should -Be 'page1'
            $rows[1].to_id | Should -Be 'user9'
            $rows[1].to_name | Should -Be 'Jane Lead'

            # the conversations call used the PAGE token, not the system-user token
            Should -Invoke Invoke-ImperionMetaRequest -Times 1 -ParameterFilter {
                $Token -eq 'page-token' -and $Uri -match '^page1/conversations\?fields='
            }
        }
    }

    It 'resolves the page token via Get-ImperionMetaPageToken when not supplied' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionMetaPageToken { 'page-token' }
            Mock Invoke-ImperionMetaRequest { @() }
            Get-ImperionMetaConversation -PageId 'page1' -Token 'sys' | Out-Null
            Should -Invoke Get-ImperionMetaPageToken -Times 1 -ParameterFilter { $PageId -eq 'page1' }
        }
    }

    It 'skips the page-token hop when -PageToken is supplied' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionMetaPageToken { throw 'must not be called' }
            Mock Invoke-ImperionMetaRequest { @() }
            Get-ImperionMetaConversation -PageId 'page1' -PageToken 'pt' | Out-Null
            Should -Invoke Invoke-ImperionMetaRequest -Times 1 -ParameterFilter { $Token -eq 'pt' }
        }
    }
}
