#Requires -Modules Pester
# Hermetic test for Get-ImperionOkfConcept: parses a temp markdown file; no DB, no network.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force

    $script:tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("okf-test-{0}" -f ([guid]::NewGuid().ToString('N')))
    New-Item -ItemType Directory -Force -Path $script:tmpDir | Out-Null
    $script:conceptFile = Join-Path $script:tmpDir 'account.md'
    @'
---
type: Silver Table
title: account
timestamp: 2026-06-14T00:00:00Z
---

# account

## Source of record / authority

Some prose with a `not_a_column` backtick that must be ignored.

## Schema

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | PK |
| `Name` | text | mixed case -> lower-cased |
| `health_score` | numeric | |

## Joins

- `account_id` referenced elsewhere (ignored — not in Schema section).
'@ | Set-Content -LiteralPath $script:conceptFile -Encoding utf8
}

AfterAll {
    if (Test-Path $script:tmpDir) { Remove-Item -Recurse -Force $script:tmpDir }
}

Describe 'Get-ImperionOkfConcept' {
    It 'extracts only the Schema-table column names, lower-cased, in order' {
        InModuleScope ImperionPipeline -Parameters @{ f = $script:conceptFile } {
            param($f)
            $r = Get-ImperionOkfConcept -Path $f
            $r.Exists | Should -BeTrue
            $r.Columns | Should -Be @('id', 'name', 'health_score')
        }
    }

    It 'reads the frontmatter timestamp' {
        InModuleScope ImperionPipeline -Parameters @{ f = $script:conceptFile } {
            param($f)
            (Get-ImperionOkfConcept -Path $f).Timestamp | Should -Be '2026-06-14T00:00:00Z'
        }
    }

    It 'ignores backticks outside the Schema section and join rows' {
        InModuleScope ImperionPipeline -Parameters @{ f = $script:conceptFile } {
            param($f)
            $cols = (Get-ImperionOkfConcept -Path $f).Columns
            $cols | Should -Not -Contain 'not_a_column'
            $cols | Should -Not -Contain 'account_id'
        }
    }

    It 'reports a missing file as not-exists with no columns' {
        InModuleScope ImperionPipeline {
            $r = Get-ImperionOkfConcept -Path (Join-Path ([System.IO.Path]::GetTempPath()) 'no-such-okf-file.md')
            $r.Exists | Should -BeFalse
            $r.Columns.Count | Should -Be 0
        }
    }
}
