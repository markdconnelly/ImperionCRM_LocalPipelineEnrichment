#Requires -Modules Pester
# Hermetic unit tests for Get-ImperionInstagramMedia + Get-ImperionInstagramComment.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionInstagramMedia' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'partner-tenant' } }
            Mock Write-ImperionLog { }
        }
    }

    It 'resolves the IG user via the page, then flattens media to the instagram_media shape' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionMetaRequest {
                if ($Uri -match 'instagram_business_account') {
                    @([pscustomobject]@{ id = 'page1'; instagram_business_account = [pscustomobject]@{ id = 'ig9' } })
                }
                else {
                    @([pscustomobject]@{
                            id                 = 'media1'
                            caption            = 'Sunset reel'
                            media_type         = 'VIDEO'
                            media_product_type = 'REELS'
                            permalink          = 'https://instagram.com/p/x'
                            media_url          = 'https://cdn/x.mp4'
                            timestamp          = '2026-06-04T18:00:00+0000'
                            like_count         = 33
                            comments_count     = 5
                            username           = 'imperionllc'
                        })
                }
            }
            $rows = @(Get-ImperionInstagramMedia -PageId 'page1' -Token 't')
            $rows.Count | Should -Be 1
            $rows[0].ig_user_id | Should -Be 'ig9'
            $rows[0].ig_username | Should -Be 'imperionllc'
            $rows[0].created_time | Should -Match '^2026-06-04'   # timestamp -> created_time
            $rows[0].media_product_type | Should -Be 'REELS'
            $rows[0].source | Should -Be 'instagram'
            $rows[0].external_id | Should -Be 'media1'
            Should -Invoke Invoke-ImperionMetaRequest -Times 1 -ParameterFilter { $Uri -match '^ig9/media\?fields=' }
        }
    }

    It 'warns and returns nothing when the page has no linked IG account' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionMetaRequest { @([pscustomobject]@{ id = 'page1' }) }
            $rows = @(Get-ImperionInstagramMedia -PageId 'page1' -Token 't')
            $rows.Count | Should -Be 0
            Should -Invoke Write-ImperionLog -Times 1 -ParameterFilter { $Level -eq 'Warn' -and $Message -match 'no linked instagram_business_account' }
        }
    }

    It '-IgUserId override skips the page hop' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionMetaRequest { @() }
            Get-ImperionInstagramMedia -IgUserId 'ig42' -Token 't' | Out-Null
            Should -Invoke Invoke-ImperionMetaRequest -Times 1 -ParameterFilter { $Uri -match '^ig42/media' }
            Should -Invoke Invoke-ImperionMetaRequest -Times 0 -ParameterFilter { $Uri -match 'instagram_business_account' }
        }
    }
}

Describe 'Get-ImperionInstagramComment' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'partner-tenant' } }
            Mock Write-ImperionLog { }
        }
    }

    It 'flattens comments to the instagram_comments shape (text->comment_text, timestamp->created_time, tolerant from)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionMetaRequest {
                @(
                    [pscustomobject]@{
                        id         = 'igc1'
                        text       = 'Love this'
                        username   = 'fan_account'
                        from       = [pscustomobject]@{ id = 'igu7' }
                        timestamp  = '2026-06-05T08:00:00+0000'
                        like_count = 1
                        parent_id  = 'igc0'
                    },
                    [pscustomobject]@{
                        id        = 'igc2'
                        text      = 'No from field on this one'
                        username  = 'other_fan'
                        timestamp = '2026-06-05T09:00:00+0000'
                    }
                )
            }
            $mediaRow = [pscustomobject]@{ external_id = 'media1' }
            $rows = @($mediaRow | Get-ImperionInstagramComment -Token 't')
            $rows.Count | Should -Be 2
            $rows[0].media_external_id | Should -Be 'media1'
            $rows[0].comment_text | Should -Be 'Love this'
            $rows[0].from_id | Should -Be 'igu7'
            $rows[0].parent_comment_id | Should -Be 'igc0'
            $rows[0].created_time | Should -Match '^2026-06-05'
            $rows[0].source | Should -Be 'instagram'
            # from is permission-gated: absent -> from_id null, username still identifies
            $rows[1].from_id | Should -BeNullOrEmpty
            $rows[1].username | Should -Be 'other_fan'
        }
    }
}
