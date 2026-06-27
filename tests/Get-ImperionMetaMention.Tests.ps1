#Requires -Modules Pester
# Hermetic unit tests for Get-ImperionMetaMention (LP #391 / front-end #1365): the FB /tagged +
# IG /tags edges, the meta_mentions flat shape, fail-soft per-network, and the Since filter.
# Connect layer + context mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionMetaMention' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'partner-tenant' } }
            Mock Write-ImperionLog { }
        }
    }

    It 'flattens an FB tagged post + an IG tagged media to the meta_mentions shape' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionMetaRequest {
                if ($Uri -match '/tagged\?') {
                    @([pscustomobject]@{
                            id            = 'fb_m1'
                            message       = 'Shout out to Imperion'
                            permalink_url = 'https://facebook.com/fb_m1'
                            from          = [pscustomobject]@{ id = 'fbu1'; name = 'Happy Client'; username = 'happyclient' }
                            created_time  = '2026-06-05T10:00:00+0000'
                        })
                }
                elseif ($Uri -match 'instagram_business_account') {
                    @([pscustomobject]@{ id = 'page1'; instagram_business_account = [pscustomobject]@{ id = 'ig9' } })
                }
                elseif ($Uri -match '/tags\?') {
                    @([pscustomobject]@{
                            id        = 'ig_m1'
                            caption   = 'Tagged @imperion in our setup'
                            permalink = 'https://instagram.com/p/ig_m1'
                            username  = 'fan_account'
                            owner     = [pscustomobject]@{ id = 'igu1' }
                            timestamp = '2026-06-06T11:00:00+0000'
                        })
                }
                else { @() }
            }

            $rows = @(Get-ImperionMetaMention -PageId 'page1' -Token 't')
            $rows.Count | Should -Be 2

            $fb = @($rows | Where-Object { $_.platform -eq 'facebook' })[0]
            $fb.mention_id | Should -Be 'fb_m1'
            $fb.mention_kind | Should -Be 'tagged_post'
            $fb.message | Should -Be 'Shout out to Imperion'
            $fb.permalink | Should -Be 'https://facebook.com/fb_m1'
            $fb.author_id | Should -Be 'fbu1'
            $fb.author_username | Should -Be 'happyclient'
            $fb.author_name | Should -Be 'Happy Client'
            $fb.raw | Should -Match 'Shout out to Imperion'

            $ig = @($rows | Where-Object { $_.platform -eq 'instagram' })[0]
            $ig.mention_id | Should -Be 'ig_m1'
            $ig.mention_kind | Should -Be 'tagged_media'
            $ig.message | Should -Be 'Tagged @imperion in our setup'
            $ig.permalink | Should -Be 'https://instagram.com/p/ig_m1'
            $ig.author_id | Should -Be 'igu1'
            $ig.author_username | Should -Be 'fan_account'
        }
    }

    It 'emits ONLY the meta_mentions columns — never the standard bronze envelope' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionMetaRequest {
                if ($Uri -match '/tagged\?') { @([pscustomobject]@{ id = 'fb_m1'; message = 'hi' }) } else { @() }
            }
            $rows = @(Get-ImperionMetaMention -PageId 'page1' -IgUserId 'ig9' -Token 't')
            $columns = $rows[0].PSObject.Properties.Name
            $columns | Should -Be @('platform', 'mention_id', 'mention_kind', 'permalink', 'message',
                'author_id', 'author_username', 'author_name', 'created_time', 'raw')
            # the standard envelope columns must NOT be present (meta_mentions has none of them)
            $columns | Should -Not -Contain 'tenant_id'
            $columns | Should -Not -Contain 'source'
            $columns | Should -Not -Contain 'content_hash'
            $columns | Should -Not -Contain 'collected_at'
            $columns | Should -Not -Contain 'raw_payload'
        }
    }

    It 'is fail-soft: an FB error still lets IG mentions through' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionMetaRequest {
                if ($Uri -match '/tagged\?') { throw 'FB permission denied' }
                elseif ($Uri -match '/tags\?') { @([pscustomobject]@{ id = 'ig_m1'; caption = 'c'; username = 'u' }) }
                else { @() }
            }
            $rows = @(Get-ImperionMetaMention -PageId 'page1' -IgUserId 'ig9' -Token 't')
            $rows.Count | Should -Be 1
            $rows[0].platform | Should -Be 'instagram'
            Should -Invoke Write-ImperionLog -Times 1 -ParameterFilter { $Level -eq 'Warn' -and $Message -match 'Facebook mention collection failed' }
        }
    }

    It 'warns and skips IG when the page has no linked instagram_business_account' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionMetaRequest {
                if ($Uri -match '/tagged\?') { @() }
                elseif ($Uri -match 'instagram_business_account') { @([pscustomobject]@{ id = 'page1' }) }
                else { @() }
            }
            $rows = @(Get-ImperionMetaMention -PageId 'page1' -Token 't')
            $rows.Count | Should -Be 0
            Should -Invoke Write-ImperionLog -Times 1 -ParameterFilter { $Message -match 'no linked instagram_business_account' }
        }
    }

    It 'passes the since filter to both edges' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionMetaRequest { @() }
            Get-ImperionMetaMention -PageId '123' -IgUserId 'ig9' -Token 't' -Since '2026-06-01T00:00:00Z' | Out-Null
            Should -Invoke Invoke-ImperionMetaRequest -Times 1 -ParameterFilter {
                $Uri -match '^123/tagged\?fields=' -and $Uri -match 'since=2026-06-01T00%3A00%3A00Z'
            }
            Should -Invoke Invoke-ImperionMetaRequest -Times 1 -ParameterFilter {
                $Uri -match '^ig9/tags\?fields=' -and $Uri -match 'since=2026-06-01T00%3A00%3A00Z'
            }
        }
    }
}
