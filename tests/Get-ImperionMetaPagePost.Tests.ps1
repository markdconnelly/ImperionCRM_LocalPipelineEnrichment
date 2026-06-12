#Requires -Modules Pester
# Hermetic unit tests for Get-ImperionMetaPagePost. Connect layer + context mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionMetaPagePost' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'partner-tenant' } }
            Mock Write-ImperionLog { }
        }
    }

    It 'flattens a post to the facebook_posts shape with the standard envelope' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionMetaRequest {
                @([pscustomobject]@{
                        id            = '123_456'
                        message       = 'Hello from the page'
                        status_type   = 'mobile_status_update'
                        permalink_url = 'https://facebook.com/123_456'
                        from          = [pscustomobject]@{ id = '123'; name = 'Imperion' }
                        created_time  = '2026-06-01T12:00:00+0000'
                        updated_time  = '2026-06-02T12:00:00+0000'
                        is_published  = $true
                        shares        = [pscustomobject]@{ count = 4 }
                        comments      = [pscustomobject]@{ summary = [pscustomobject]@{ total_count = 7 } }
                        reactions     = [pscustomobject]@{ summary = [pscustomobject]@{ total_count = 21 } }
                    })
            }
            $rows = @(Get-ImperionMetaPagePost -PageId '123' -Token 't')
            $rows.Count | Should -Be 1
            $rows[0].page_id | Should -Be '123'
            $rows[0].message | Should -Be 'Hello from the page'
            $rows[0].from_id | Should -Be '123'
            $rows[0].from_name | Should -Be 'Imperion'
            $rows[0].comment_count | Should -Be '7'
            $rows[0].reaction_count | Should -Be '21'
            $rows[0].share_count | Should -Be '4'
            $rows[0].is_published | Should -Be 'true'
            $rows[0].source | Should -Be 'facebook'
            $rows[0].tenant_id | Should -Be 'partner-tenant'
            $rows[0].external_id | Should -Be '123_456'
            $rows[0].content_hash | Should -Not -BeNullOrEmpty
            $rows[0].raw_payload | Should -Match 'Hello from the page'
        }
    }

    It 'survives missing fields: flat columns land null, raw_payload keeps everything' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionMetaRequest { @([pscustomobject]@{ id = 'p9'; surpriseField = 'x' }) }
            $rows = @(Get-ImperionMetaPagePost -PageId '123' -Token 't')
            $rows[0].message | Should -BeNullOrEmpty
            $rows[0].comment_count | Should -BeNullOrEmpty
            $rows[0].external_id | Should -Be 'p9'
            $rows[0].raw_payload | Should -Match 'surpriseField'
        }
    }

    It 'passes the since filter and the summary field list' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionMetaRequest { @() }
            Get-ImperionMetaPagePost -PageId '123' -Token 't' -Since '2026-06-01T00:00:00Z' | Out-Null
            Should -Invoke Invoke-ImperionMetaRequest -Times 1 -ParameterFilter {
                $Uri -match '^123/posts\?fields=' -and
                $Uri -match 'comments\.summary\(true\)\.limit\(0\)' -and
                $Uri -match 'since=2026-06-01T00%3A00%3A00Z'
            }
        }
    }
}

Describe 'Get-ImperionMetaPostComment' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'partner-tenant' } }
            Mock Write-ImperionLog { }
        }
    }

    It 'takes post rows from the pipeline (binds external_id) and stamps post_external_id + parent' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionMetaRequest {
                @([pscustomobject]@{
                        id           = 'c1'
                        message      = 'Nice post'
                        from         = [pscustomobject]@{ id = 'u9'; name = 'Commenter' }
                        created_time = '2026-06-03T09:00:00+0000'
                        like_count   = 2
                        parent       = [pscustomobject]@{ id = 'c0' }
                    })
            }
            $postRow = [pscustomobject]@{ external_id = '123_456'; message = 'post row' }
            $rows = @($postRow | Get-ImperionMetaPostComment -Token 't')
            $rows.Count | Should -Be 1
            $rows[0].post_external_id | Should -Be '123_456'
            $rows[0].parent_comment_id | Should -Be 'c0'
            $rows[0].from_id | Should -Be 'u9'
            $rows[0].source | Should -Be 'facebook'
            $rows[0].external_id | Should -Be 'c1'
            Should -Invoke Invoke-ImperionMetaRequest -Times 1 -ParameterFilter { $Uri -match '^123_456/comments\?fields=' }
        }
    }

    It 'fans an explicit -PostId array, one comments call per post' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionMetaRequest { @() }
            Get-ImperionMetaPostComment -PostId 'a', 'b' -Token 't' | Out-Null
            Should -Invoke Invoke-ImperionMetaRequest -Times 2
        }
    }
}
