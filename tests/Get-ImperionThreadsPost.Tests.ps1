#Requires -Modules Pester
# Hermetic unit tests for the threads get-layer collectors. Connect layer + context + token
# resolution mocked in module scope (LocalPipeline #356, front-end migration 0208).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionThreadsPost' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'partner-tenant' } }
            Mock Resolve-ImperionThreadsToken { 't' }
            Mock Write-ImperionLog { }
        }
    }

    It 'flattens a post to the threads_posts shape with the standard envelope' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionThreadsRequest {
                @([pscustomobject]@{
                        id             = '178414'
                        username       = 'imperion'
                        text           = 'Hello from Threads'
                        media_type     = 'TEXT_POST'
                        permalink      = 'https://threads.net/t/178414'
                        shortcode      = 'abc'
                        timestamp      = '2026-06-01T12:00:00+0000'
                        is_quote_post  = $false
                        reply_audience = 'everyone'
                        owner          = [pscustomobject]@{ id = 'u1' }
                    })
            }
            $rows = @(Get-ImperionThreadsPost -Token 't')
            $rows.Count | Should -Be 1
            $rows[0].threads_user_id | Should -Be 'u1'
            $rows[0].username | Should -Be 'imperion'
            $rows[0].text_content | Should -Be 'Hello from Threads'
            $rows[0].media_type | Should -Be 'TEXT_POST'
            $rows[0].reply_audience | Should -Be 'everyone'
            $rows[0].source | Should -Be 'threads'
            $rows[0].tenant_id | Should -Be 'partner-tenant'
            $rows[0].external_id | Should -Be '178414'
            $rows[0].content_hash | Should -Not -BeNullOrEmpty
            $rows[0].raw_payload | Should -Match 'Hello from Threads'
        }
    }

    It 'survives missing fields: flat columns land null, raw_payload keeps everything' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionThreadsRequest { @([pscustomobject]@{ id = 'p9'; surpriseField = 'x' }) }
            $rows = @(Get-ImperionThreadsPost -Token 't')
            $rows[0].text_content | Should -BeNullOrEmpty
            $rows[0].external_id | Should -Be 'p9'
            $rows[0].raw_payload | Should -Match 'surpriseField'
        }
    }

    It 'passes the since filter against the me/threads edge' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionThreadsRequest { @() }
            Get-ImperionThreadsPost -Token 't' -Since '2026-06-01T00:00:00Z' | Out-Null
            Should -Invoke Invoke-ImperionThreadsRequest -Times 1 -ParameterFilter {
                $Uri -match '^me/threads\?fields=' -and $Uri -match 'since=2026-06-01T00%3A00%3A00Z'
            }
        }
    }
}

Describe 'Get-ImperionThreadsReply' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'partner-tenant' } }
            Mock Resolve-ImperionThreadsToken { 't' }
            Mock Write-ImperionLog { }
        }
    }

    It 'takes post rows from the pipeline (binds external_id) and stamps root_post_external_id' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionThreadsRequest {
                @([pscustomobject]@{
                        id         = 'r1'
                        username   = 'fan'
                        text       = 'nice'
                        timestamp  = '2026-06-03T09:00:00+0000'
                        replied_to = [pscustomobject]@{ id = 'r0' }
                        owner      = [pscustomobject]@{ id = 'u9' }
                    })
            }
            $postRow = [pscustomobject]@{ external_id = '178414'; text_content = 'post row' }
            $rows = @($postRow | Get-ImperionThreadsReply -Token 't')
            $rows.Count | Should -Be 1
            $rows[0].root_post_external_id | Should -Be '178414'
            $rows[0].replied_to_external_id | Should -Be 'r0'
            $rows[0].threads_user_id | Should -Be 'u9'
            $rows[0].source | Should -Be 'threads'
            $rows[0].external_id | Should -Be 'r1'
            Should -Invoke Invoke-ImperionThreadsRequest -Times 1 -ParameterFilter { $Uri -match '^178414/replies\?fields=' }
        }
    }

    It 'fans an explicit -PostId array, one replies call per post' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionThreadsRequest { @() }
            Get-ImperionThreadsReply -PostId 'a', 'b' -Token 't' | Out-Null
            Should -Invoke Invoke-ImperionThreadsRequest -Times 2
        }
    }
}

Describe 'Get-ImperionThreadsMention' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'partner-tenant' } }
            Mock Resolve-ImperionThreadsToken { 't' }
            Mock Write-ImperionLog { }
        }
    }

    It 'flattens a mention to the threads_mentions shape against me/mentions' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionThreadsRequest {
                @([pscustomobject]@{
                        id        = 'm1'
                        username  = 'someone'
                        text      = '@imperion great work'
                        permalink = 'https://threads.net/t/m1'
                        timestamp = '2026-06-04T10:00:00+0000'
                        owner     = [pscustomobject]@{ id = 'u5' }
                    })
            }
            $rows = @(Get-ImperionThreadsMention -Token 't')
            $rows.Count | Should -Be 1
            $rows[0].mentioned_post_external_id | Should -Be 'm1'
            $rows[0].threads_user_id | Should -Be 'u5'
            $rows[0].username | Should -Be 'someone'
            $rows[0].source | Should -Be 'threads'
            $rows[0].external_id | Should -Be 'm1'
            Should -Invoke Invoke-ImperionThreadsRequest -Times 1 -ParameterFilter { $Uri -match '^me/mentions\?fields=' }
        }
    }
}

Describe 'Get-ImperionThreadsInsight' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'partner-tenant' } }
            Mock Resolve-ImperionThreadsToken { 't' }
            Mock Write-ImperionLog { }
        }
    }

    It 'flattens profile total_value metrics to one dated point per metric' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionThreadsRequest {
                @([pscustomobject]@{ name = 'views'; period = 'lifetime'; total_value = [pscustomobject]@{ value = 42 } })
            }
            $rows = @(Get-ImperionThreadsInsight -ThreadsUserId 'u1' -ProfileMetric @('views') -PostMetric @())
            $rows.Count | Should -Be 1
            $rows[0].entity_kind | Should -Be 'profile'
            $rows[0].entity_external_id | Should -Be 'u1'
            $rows[0].metric | Should -Be 'views'
            $rows[0].value | Should -Be '42'
            $rows[0].source | Should -Be 'threads'
            $rows[0].external_id | Should -Match '^profile:u1:views:lifetime:'
        }
    }

    It 'continues past a failing metric (deprecation tolerance)' {
        InModuleScope ImperionPipeline {
            $script:calls = 0
            Mock Invoke-ImperionThreadsRequest {
                $script:calls++
                if ($script:calls -eq 1) { throw 'dead metric' }
                @([pscustomobject]@{ name = 'likes'; period = 'lifetime'; total_value = [pscustomobject]@{ value = 5 } })
            }
            $rows = @(Get-ImperionThreadsInsight -ThreadsUserId 'u1' -ProfileMetric @('views', 'likes') -PostMetric @())
            $rows.Count | Should -Be 1
            $rows[0].metric | Should -Be 'likes'
            Should -Invoke Write-ImperionLog -Times 1 -ParameterFilter { $Level -eq 'Warn' }
        }
    }

    It 'pulls per-post insights for piped post ids' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionThreadsRequest {
                @([pscustomobject]@{ name = 'views'; total_value = [pscustomobject]@{ value = 1 } })
            }
            $postRow = [pscustomobject]@{ external_id = 'post7' }
            $rows = @($postRow | Get-ImperionThreadsInsight -PostMetric @('views'))
            $rows[0].entity_kind | Should -Be 'post'
            $rows[0].entity_external_id | Should -Be 'post7'
            Should -Invoke Invoke-ImperionThreadsRequest -ParameterFilter { $Uri -match '^post7/insights\?' }
        }
    }
}
