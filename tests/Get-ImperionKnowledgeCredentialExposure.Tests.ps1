#Requires -Modules Pester
# Hermetic tests for Get-ImperionKnowledgeCredentialExposure: DB layer mocked.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionKnowledgeCredentialExposure' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'tenant-1' } }
            Mock Write-ImperionLog {}
            Mock Invoke-ImperionDbQuery {
                @([pscustomobject]@{
                    id = 'exp-1'; email = 'jane@acme.com'; breach_source = 'LinkedIn 2021'
                    breach_date = '2021-06-22'; exposed_data = 'email, password'
                    password_status = 'hashed'; severity = 'high'; status = 'new'
                    first_seen_at = '2026-05-01'; last_seen_at = '2026-06-01'
                    contact_name = 'Jane Doe'; account_name = 'Acme Corp'; bronze_records = 2
                })
            }
        }
    }

    It 'composes one knowledge_object row per exposure with the exposure facts' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionKnowledgeCredentialExposure -Connection ([pscustomobject]@{}))
            $rows.Count           | Should -Be 1
            $rows[0].entity_type  | Should -Be 'exposure'
            $rows[0].entity_ref   | Should -Be 'exp-1'
            $rows[0].tenant_id    | Should -Be 'tenant-1'
            $rows[0].source       | Should -Be 'darkwebid'
            $rows[0].title        | Should -Be 'Credential exposure: jane@acme.com — LinkedIn 2021'
            $rows[0].body         | Should -Match 'domain: acme\.com'
            $rows[0].body         | Should -Match 'source breach: LinkedIn 2021'
            $rows[0].body         | Should -Match 'breach date: 2021-06-22'
            $rows[0].body         | Should -Match 'Exposed data classes: email, password'
            $rows[0].body         | Should -Match 'status: new'
            $rows[0].content_hash | Should -Match '^[0-9a-f]{64}$'
        }
    }

    It 'keeps plaintext credentials out of gold — only the password status word appears' {
        InModuleScope ImperionPipeline {
            # The composer must summarize facts, never read payload_bronze (raw breach
            # payloads can carry the actual password).
            $row = @(Get-ImperionKnowledgeCredentialExposure -Connection ([pscustomobject]@{}))[0]
            $row.body | Should -Match 'Password status: hashed'
            Should -Invoke Invoke-ImperionDbQuery -Times 1 -Exactly -ParameterFilter {
                $Sql -notmatch 'payload_bronze'
            }
        }
    }

    It 'has the knowledge metadata shape and a stable content hash' {
        InModuleScope ImperionPipeline {
            $first  = @(Get-ImperionKnowledgeCredentialExposure -Connection ([pscustomobject]@{}))[0]
            $second = @(Get-ImperionKnowledgeCredentialExposure -Connection ([pscustomobject]@{}))[0]
            $first.content_hash | Should -Be $second.content_hash
            $metadata = $first.metadata | ConvertFrom-Json
            $metadata.account        | Should -Be 'Acme Corp'
            $metadata.severity       | Should -Be 'high'
            $metadata.status         | Should -Be 'new'
            $metadata.bronze_records | Should -Be 2
        }
    }

    It 'returns nothing (and does not throw) when silver is empty' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { @() }
            @(Get-ImperionKnowledgeCredentialExposure -Connection ([pscustomobject]@{})) | Should -BeNullOrEmpty
        }
    }
}
