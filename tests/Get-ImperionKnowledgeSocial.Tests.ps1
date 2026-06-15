#Requires -Modules Pester
# Hermetic tests for Get-ImperionKnowledgeSocial: DB layer mocked.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionKnowledgeSocial' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'tenant-1' } }
            Mock Write-ImperionLog {}
            Mock Invoke-ImperionDbQuery {
                @(
                    [pscustomobject]@{
                        id = '101'; source = 'facebook'; kind = 'social_post'; direction = 'outbound'
                        subject = 'New service launch'; occurred_at = '2026-06-10T12:00:00Z'
                        message = 'We just launched managed backup for SMBs!'; caption = $null
                        comment_text = $null; from_name = $null; username = $null
                        permalink = $null; permalink_url = 'https://fb.com/p/1'
                        like_count = '12'; comment_count = '3'; comments_count = $null
                        reaction_count = '15'; share_count = '2'; contact_name = $null
                    },
                    [pscustomobject]@{
                        id = '102'; source = 'instagram'; kind = 'social_comment'; direction = 'inbound'
                        subject = 'Do you cover Macs?'; occurred_at = '2026-06-11T08:30:00Z'
                        message = $null; caption = $null
                        comment_text = 'Do you cover Macs?'; from_name = $null; username = 'jane_doe'
                        permalink = 'https://instagram.com/c/2'; permalink_url = $null
                        like_count = '1'; comment_count = $null; comments_count = $null
                        reaction_count = $null; share_count = $null; contact_name = $null
                    },
                    [pscustomobject]@{
                        id = '103'; source = 'facebook'; kind = 'dm'; direction = 'inbound'
                        subject = 'Need a quote'; occurred_at = '2026-06-12T09:00:00Z'
                        message = 'Hi, can you send a quote for 20 seats?'; caption = $null
                        comment_text = $null; from_name = 'Bob Lead'; username = $null
                        permalink = $null; permalink_url = $null
                        like_count = $null; comment_count = $null; comments_count = $null
                        reaction_count = $null; share_count = $null; contact_name = 'Bob Lead'
                    }
                )
            }
        }
    }

    It 'composes one social knowledge_object row per interaction' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionKnowledgeSocial -Connection ([pscustomobject]@{}))
            $rows.Count          | Should -Be 3
            $rows[0].entity_type | Should -Be 'social'
            ($rows.entity_ref)   | Should -Be @('101', '102', '103')
            $rows[0].content_hash | Should -Match '^[0-9a-f]{64}$'
        }
    }

    It 'stamps the platform source and folds text + engagement into the body' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionKnowledgeSocial -Connection ([pscustomobject]@{}))
            $post = $rows | Where-Object entity_ref -eq '101'
            $post.source       | Should -Be 'facebook'
            $post.title        | Should -Match 'Facebook post'
            $post.body         | Should -Match 'managed backup'
            $post.body         | Should -Match 'likes: 12'
            $post.body         | Should -Match 'reactions: 15'
            $post.body         | Should -Match 'Link: https://fb.com/p/1'
        }
    }

    It 'prefers comment_text and the username author for a comment' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionKnowledgeSocial -Connection ([pscustomobject]@{}))
            $comment = $rows | Where-Object entity_ref -eq '102'
            $comment.title | Should -Match 'Instagram comment'
            $comment.body  | Should -Match 'From: jane_doe'
            $comment.body  | Should -Match 'Do you cover Macs'
        }
    }

    It 'surfaces the resolved contact name for a DM lead and labels direction' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionKnowledgeSocial -Connection ([pscustomobject]@{}))
            $dm = $rows | Where-Object entity_ref -eq '103'
            $dm.title | Should -Match 'Facebook direct message'
            $dm.body  | Should -Match 'inbound'
            $dm.body  | Should -Match 'From: Bob Lead'
            ($dm.metadata | ConvertFrom-Json).contact | Should -Be 'Bob Lead'
        }
    }

    It 'returns nothing (and does not throw) when silver has no social interactions' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { @() }
            @(Get-ImperionKnowledgeSocial -Connection ([pscustomobject]@{})) | Should -BeNullOrEmpty
        }
    }
}
