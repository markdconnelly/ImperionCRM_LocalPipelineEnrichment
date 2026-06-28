#Requires -Modules Pester
# Hermetic tests for Get-ImperionKnowledgePosture: DB layer + drift cmdlet mocked.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionKnowledgePosture' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'tenant-1' } }
            Mock Write-ImperionLog {}
            # Route the tenant enumeration and the latest-secure-score queries.
            Mock Invoke-ImperionDbQuery {
                if ($Sql -match 'posture_tenants') {
                    return @(
                        [pscustomobject]@{ tenant_id = 'tenant-1' }
                        [pscustomobject]@{ tenant_id = 'tenant-2' }
                    )
                }
                if ($Sql -match 'FROM secure_scores') {
                    return @([pscustomobject]@{
                        tenant_id = 'tenant-1'; current_score = '412.5'; max_score = '600'
                        created_date_time = '2026-06-08T04:00:00Z'
                    })
                }
                return @()
            }
            # Reuse seam: the composer classifies via the existing drift cmdlet.
            Mock Get-ImperionPolicyDrift {
                if ($TenantId -ne 'tenant-1') { return @() }
                @(
                    [pscustomobject]@{ policy_type = 'conditional-access'; policy_id = 'ca-1'; policy_name = 'Require MFA for admins'; status = 'compliant'; current_hash = 'h1'; golden_hash = 'h1' }
                    [pscustomobject]@{ policy_type = 'conditional-access'; policy_id = 'ca-2'; policy_name = 'Block legacy auth'; status = 'drift'; current_hash = 'h2'; golden_hash = 'h3' }
                    [pscustomobject]@{ policy_type = 'intune-security'; policy_id = 'in-1'; policy_name = 'BitLocker baseline'; status = 'missing'; current_hash = $null; golden_hash = 'h4' }
                    [pscustomobject]@{ policy_type = 'intune-security'; policy_id = 'in-2'; policy_name = 'EDR onboarding'; status = 'ungoverned'; current_hash = 'h5'; golden_hash = $null }
                )
            }
        }
    }

    It 'composes one knowledge_object row per tenant, stamped with ITS tenant' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionKnowledgePosture -Connection ([pscustomobject]@{}))
            $rows.Count          | Should -Be 2
            $rows[0].entity_type | Should -Be 'posture'
            $rows[0].entity_ref  | Should -Be 'tenant-1'
            $rows[0].tenant_id   | Should -Be 'tenant-1'
            $rows[1].tenant_id   | Should -Be 'tenant-2'
            $rows[0].source      | Should -Be 'local-pipeline'
            $rows[0].content_hash | Should -Match '^[0-9a-f]{64}$'
        }
    }

    It 'writes the score, per-type drift counts, and named gaps into the body' {
        InModuleScope ImperionPipeline {
            $row = @(Get-ImperionKnowledgePosture -Connection ([pscustomobject]@{}))[0]
            $row.body | Should -Match 'Secure Score: 412\.5 of 600 \(68\.8%\)'
            $row.body | Should -Match 'conditional-access: 2 policies — compliant 1 · drift 1'
            $row.body | Should -Match 'intune-security: 2 policies — ungoverned 1 · missing 1'
            $row.body | Should -Match 'Notable gaps \(3 policies not compliant with baseline\):'
            $row.body | Should -Match '\[conditional-access\] Block legacy auth — drift'
            $row.body | Should -Match '\[intune-security\] BitLocker baseline — missing'
            $row.body | Should -Match '\[intune-security\] EDR onboarding — ungoverned'
        }
    }

    It 'degrades gracefully for a tenant with no score and no policies' {
        InModuleScope ImperionPipeline {
            $row = @(Get-ImperionKnowledgePosture -Connection ([pscustomobject]@{}))[1]
            $row.body | Should -Match 'Secure Score: no snapshot collected yet\.'
            $row.body | Should -Match 'No security-posture policies observed for this tenant yet\.'
        }
    }

    It 'has the knowledge metadata shape and a stable content hash' {
        InModuleScope ImperionPipeline {
            $first  = @(Get-ImperionKnowledgePosture -Connection ([pscustomobject]@{}))[0]
            $second = @(Get-ImperionKnowledgePosture -Connection ([pscustomobject]@{}))[0]
            $first.content_hash | Should -Be $second.content_hash
            $metadata = $first.metadata | ConvertFrom-Json
            $metadata.secure_score | Should -Be '412.5'
            $metadata.policies     | Should -Be 4
            $metadata.compliant    | Should -Be 1
            $metadata.drift        | Should -Be 1
            $metadata.ungoverned   | Should -Be 1
            $metadata.missing      | Should -Be 1
        }
    }

    It 'restricts to one tenant when -TenantId is passed' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionKnowledgePosture -Connection ([pscustomobject]@{}) -TenantId 'tenant-2')
            $rows.Count        | Should -Be 1
            $rows[0].tenant_id | Should -Be 'tenant-2'
        }
    }

    It 'returns nothing (and does not throw) when no posture bronze exists' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { @() }
            @(Get-ImperionKnowledgePosture -Connection ([pscustomobject]@{})) | Should -BeNullOrEmpty
        }
    }
}
