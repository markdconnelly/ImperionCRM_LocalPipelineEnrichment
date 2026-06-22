#Requires -Modules Pester
# Hermetic tests for Get-ImperionKnowledgeSemanticConcept: reads a throwaway on-disk bundle
# (the composer's only input is the filesystem — no DB). Proves the per-concept gold
# `semantic_concept` knowledge_object emit (entity_ref = concept basename — the drill-down key),
# frontmatter→title/summary/metadata parsing, frontmatter-stripped prose body, the content_hash
# idempotency key, the partner-tenant default, and the empty / body-less short-circuits.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force

    $script:bundleRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("imperion-okf-test-{0}" -f ([guid]::NewGuid().ToString('N')))
    $script:tablesDir = Join-Path $bundleRoot 'tables'
    New-Item -ItemType Directory -Force -Path $tablesDir | Out-Null

    Set-Content -LiteralPath (Join-Path $tablesDir 'account.md') -Value @'
---
type: OKF Concept
title: Account
description: The unified customer company record.
tags: [semantic-layer, okf, kernel, account]
timestamp: 2026-06-19T00:00:00Z
---

# Account

The kernel customer record referenced everywhere.

## Source of record / authority
Autotask wins for billing fields; website manual edits outrank machine sources.
'@

    Set-Content -LiteralPath (Join-Path $tablesDir 'contact.md') -Value @'
---
type: OKF Concept
title: Contact
description: A person at a customer account.
tags: [semantic-layer, okf, kernel, contact]
timestamp: 2026-06-19T00:00:00Z
---

# Contact

A person associated with an account.
'@

    # Frontmatter only, no prose — must be skipped (NOT NULL body).
    Set-Content -LiteralPath (Join-Path $tablesDir 'empty_body.md') -Value @'
---
title: Empty
description: no body here
---
'@
}

AfterAll {
    if (Test-Path $script:bundleRoot) { Remove-Item -Recurse -Force $script:bundleRoot -ErrorAction SilentlyContinue }
}

Describe 'Get-ImperionKnowledgeSemanticConcept' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'tenant-1' } }
            Mock Write-ImperionLog {}
        }
    }

    It 'composes one gold semantic_concept knowledge_object per concept file, keyed on the basename' {
        InModuleScope ImperionPipeline -Parameters @{ bundleRoot = $script:bundleRoot } {
            param($bundleRoot)
            $rows = @(Get-ImperionKnowledgeSemanticConcept -BundlePath $bundleRoot)
            $rows.Count           | Should -Be 2          # empty_body.md skipped (no prose)
            $rows[0].entity_type  | Should -Be 'semantic_concept'
            ($rows.entity_ref)    | Should -Be @('account', 'contact')
            $rows[0].source       | Should -Be 'okf_semantic_layer'
            $rows[0].content_hash | Should -Match '^[0-9a-f]{64}$'
            $rows[0].tenant_id    | Should -Be 'tenant-1'
        }
    }

    It 'pulls title + summary from frontmatter and strips the frontmatter out of the body' {
        InModuleScope ImperionPipeline -Parameters @{ bundleRoot = $script:bundleRoot } {
            param($bundleRoot)
            $account = @(Get-ImperionKnowledgeSemanticConcept -BundlePath $bundleRoot) | Where-Object entity_ref -eq 'account'
            $account.title   | Should -Be 'Account'
            $account.summary | Should -Be 'The unified customer company record.'
            $account.body    | Should -Match '# Account'
            $account.body    | Should -Match 'Source of record / authority'
            $account.body    | Should -Not -Match 'tags:'      # frontmatter stripped
            $account.body    | Should -Not -Match 'timestamp:'
        }
    }

    It 'carries the frontmatter facets + source-doc back-reference in metadata' {
        InModuleScope ImperionPipeline -Parameters @{ bundleRoot = $script:bundleRoot } {
            param($bundleRoot)
            $account = @(Get-ImperionKnowledgeSemanticConcept -BundlePath $bundleRoot) | Where-Object entity_ref -eq 'account'
            $meta = $account.metadata | ConvertFrom-Json
            $meta.concept    | Should -Be 'account'
            $meta.title      | Should -Be 'Account'
            $meta.okf_type   | Should -Be 'OKF Concept'
            $meta.tags       | Should -Contain 'kernel'
            $meta.source_doc | Should -Be 'docs/database/semantic-layer/tables/account.md'
        }
    }

    It 'honours an explicit -TenantId over the partner default' {
        InModuleScope ImperionPipeline -Parameters @{ bundleRoot = $script:bundleRoot } {
            param($bundleRoot)
            $rows = @(Get-ImperionKnowledgeSemanticConcept -BundlePath $bundleRoot -TenantId 'tenant-x')
            $rows[0].tenant_id | Should -Be 'tenant-x'
        }
    }

    It 'returns nothing (and does not throw) when the bundle tables dir has no concept files' {
        InModuleScope ImperionPipeline {
            $emptyDir = Join-Path ([System.IO.Path]::GetTempPath()) ("imperion-okf-empty-{0}" -f ([guid]::NewGuid().ToString('N')))
            New-Item -ItemType Directory -Force -Path (Join-Path $emptyDir 'tables') | Out-Null
            try { @(Get-ImperionKnowledgeSemanticConcept -BundlePath $emptyDir) | Should -BeNullOrEmpty }
            finally { Remove-Item -Recurse -Force $emptyDir -ErrorAction SilentlyContinue }
        }
    }
}
