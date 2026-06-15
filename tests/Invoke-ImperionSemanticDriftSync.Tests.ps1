#Requires -Modules Pester
# Hermetic test for the semantic-drift proposal + sync: detection is mocked; no DB, no network,
# no gh, no token. Asserts the dry-run / fail-closed / PII-free guarantees of issue #175.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'New-ImperionSemanticDriftProposal' {
    It 'returns a null proposal when nothing is actionable' {
        InModuleScope ImperionPipeline {
            $p = New-ImperionSemanticDriftProposal -Drift @([pscustomobject]@{ concept = 'a'; status = 'in-sync'; added_columns = @(); removed_columns = @() })
            $p.Concepts.Count | Should -Be 0
            $p.Opened | Should -BeFalse
        }
    }

    It 'builds a column-name-only proposal body (no DDL/PII) and opens nothing without -Execute' {
        InModuleScope ImperionPipeline {
            $drift = @(
                [pscustomobject]@{ concept = 'account'; status = 'drift'; added_columns = @('health_score'); removed_columns = @('legacy_col') }
                [pscustomobject]@{ concept = 'widget'; status = 'missing-concept'; added_columns = @(); removed_columns = @(); relation = 'widget' }
            )
            $p = New-ImperionSemanticDriftProposal -Drift $drift
            $p.Opened | Should -BeFalse
            $p.Concepts | Should -Contain 'account'
            $p.Body | Should -Match 'health_score'
            $p.Body | Should -Match 'tables/account.md'
            $p.Body | Should -Match 'ADR-0086'
        }
    }

    It 'fails closed (logs Warn, opens nothing) when -Execute but no token is present' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog {}
            $saved = $env:IMPERION_GH_TOKEN
            Remove-Item Env:\IMPERION_GH_TOKEN -ErrorAction SilentlyContinue
            try {
                $drift = @([pscustomobject]@{ concept = 'account'; status = 'drift'; added_columns = @('c'); removed_columns = @() })
                $p = New-ImperionSemanticDriftProposal -Drift $drift -Execute
                $p.Opened | Should -BeFalse
                $p.Mode | Should -Be 'fail-closed'
                Should -Invoke Write-ImperionLog -ParameterFilter { $Level -eq 'Warn' } -Times 1
            }
            finally { if ($saved) { $env:IMPERION_GH_TOKEN = $saved } }
        }
    }

    It 'routes mechanical drift to the PR-opener (issue #190), never gh issue create' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog {}
            Mock New-ImperionSemanticDriftPullRequest { [pscustomobject]@{ Opened = $true; Url = 'https://github.com/markdconnelly/ImperionCRM/pull/999'; Branch = 'b'; ClonePath = $null; EditedConcepts = @('account') } }
            $saved = $env:IMPERION_GH_TOKEN
            $env:IMPERION_GH_TOKEN = 'test-token-not-real'
            try {
                $drift = @([pscustomobject]@{ concept = 'account'; status = 'drift'; added_columns = @('health_score'); removed_columns = @() })
                $p = New-ImperionSemanticDriftProposal -Drift $drift -Execute
                $p.Mode | Should -Be 'pr'
                $p.Opened | Should -BeTrue
                $p.Url | Should -Match 'pull/999'
                Should -Invoke New-ImperionSemanticDriftPullRequest -Times 1
            }
            finally { if ($saved) { $env:IMPERION_GH_TOKEN = $saved } else { Remove-Item Env:\IMPERION_GH_TOKEN -ErrorAction SilentlyContinue } }
        }
    }

    It 'falls back to an issue when drift is only author-required (missing/orphaned concepts)' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog {}
            Mock New-ImperionSemanticDriftPullRequest { throw 'PR-opener must not be called for author-only drift' }
            Mock gh { $global:LASTEXITCODE = 0; 'https://github.com/markdconnelly/ImperionCRM/issues/1000' }
            $saved = $env:IMPERION_GH_TOKEN
            $env:IMPERION_GH_TOKEN = 'test-token-not-real'
            try {
                $drift = @([pscustomobject]@{ concept = 'widget'; status = 'missing-concept'; added_columns = @(); removed_columns = @(); relation = 'widget' })
                $p = New-ImperionSemanticDriftProposal -Drift $drift -Execute
                $p.Mode | Should -Be 'issue'
                Should -Invoke New-ImperionSemanticDriftPullRequest -Times 0
            }
            finally { if ($saved) { $env:IMPERION_GH_TOKEN = $saved } else { Remove-Item Env:\IMPERION_GH_TOKEN -ErrorAction SilentlyContinue } }
        }
    }
}

Describe 'Edit-ImperionOkfConceptFile' {
    It 'adds a column row, removes a gone column, and bumps the timestamp (names only, no DDL)' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog {}
            $f = Join-Path ([System.IO.Path]::GetTempPath()) ('concept-{0}.md' -f ([guid]::NewGuid().ToString('N')))
            $sampleText = @(
                '---', 'type: Silver Table', 'title: account', 'timestamp: 2026-01-01T00:00:00Z', '---', '',
                '# account', '', '## Schema', '', '| Column | Type | Notes |', '|---|---|---|',
                '| `id` | uuid | PK |', '| `legacy_col` | text | to be removed |', '', '## Joins', '', '- something'
            ) -join "`n"
            [System.IO.File]::WriteAllText($f, $sampleText)
            try {
                $changed = Edit-ImperionOkfConceptFile -Path $f -AddedColumns @('health_score') -RemovedColumns @('legacy_col') -Timestamp '2026-06-15T00:00:00Z'
                $changed | Should -BeTrue
                $out = Get-Content -LiteralPath $f -Raw
                $out | Should -Match 'timestamp: 2026-06-15T00:00:00Z'
                $out | Should -Match '`health_score`'
                $out | Should -Not -Match '`legacy_col`'
                # column NAME only — the added row uses a placeholder type, no type/DDL invented.
                $out | Should -Match '_\(\?\)_'
                # the added row sits inside Schema, before Joins.
                ($out.IndexOf('health_score')) | Should -BeLessThan ($out.IndexOf('## Joins'))
            }
            finally { Remove-Item -LiteralPath $f -ErrorAction SilentlyContinue }
        }
    }

    It 'rejects a non-identifier column name (no markdown/DDL injection)' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog {}
            $f = Join-Path ([System.IO.Path]::GetTempPath()) ('concept-{0}.md' -f ([guid]::NewGuid().ToString('N')))
            $sampleText = @(
                '---', 'type: Silver Table', 'title: account', 'timestamp: 2026-01-01T00:00:00Z', '---', '',
                '# account', '', '## Schema', '', '| Column | Type | Notes |', '|---|---|---|',
                '| `id` | uuid | PK |', '| `legacy_col` | text | to be removed |', '', '## Joins', '', '- something'
            ) -join "`n"
            [System.IO.File]::WriteAllText($f, $sampleText)
            try {
                Edit-ImperionOkfConceptFile -Path $f -AddedColumns @('a | b ; DROP TABLE x') -Timestamp '2026-06-15T00:00:00Z' | Out-Null
                $out = Get-Content -LiteralPath $f -Raw
                $out | Should -Not -Match 'DROP TABLE'
            }
            finally { Remove-Item -LiteralPath $f -ErrorAction SilentlyContinue }
        }
    }
}

Describe 'New-ImperionSemanticDriftPullRequest' {
    It 'fails closed (no token) without cloning or pushing' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog {}
            Mock git { throw 'git must not run without a token' }
            $saved = $env:IMPERION_GH_TOKEN
            Remove-Item Env:\IMPERION_GH_TOKEN -ErrorAction SilentlyContinue
            try {
                $r = New-ImperionSemanticDriftPullRequest -Drift @([pscustomobject]@{ concept = 'account'; status = 'drift'; added_columns = @('c'); removed_columns = @() }) -Title 't' -Body 'b'
                $r.Opened | Should -BeFalse
                Should -Invoke git -Times 0
            }
            finally { if ($saved) { $env:IMPERION_GH_TOKEN = $saved } }
        }
    }

    It 'with -WhatIf clones+branches+edits but never pushes or opens a PR' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog {}
            # Stand up a fake local "clone" the mocked git clone resolves to, with a real concept file.
            Mock git {
                if ($args -contains 'clone') {
                    $dest = $args[-1]
                    New-Item -ItemType Directory -Force -WhatIf:$false -Path (Join-Path $dest 'docs/database/semantic-layer/tables') | Out-Null
                    $concept = @('---', 'timestamp: 2026-01-01T00:00:00Z', '---', '', '## Schema', '| Column | Type | Notes |', '|---|---|---|', '| `id` | uuid | PK |') -join "`n"
                    [System.IO.File]::WriteAllText((Join-Path $dest 'docs/database/semantic-layer/tables/account.md'), $concept)
                    [System.IO.File]::WriteAllText((Join-Path $dest 'docs/database/semantic-layer/coverage-matrix.md'), (@('---', 'timestamp: 2026-01-01T00:00:00Z', '---') -join "`n"))
                }
                $global:LASTEXITCODE = 0
            }
            Mock gh { throw 'gh pr create must NOT run under -WhatIf' }

            $saved = $env:IMPERION_GH_TOKEN
            $env:IMPERION_GH_TOKEN = 'test-token-not-real'
            $r = $null
            try {
                $drift = @([pscustomobject]@{ concept = 'account'; status = 'drift'; added_columns = @('health_score'); removed_columns = @() })
                $r = New-ImperionSemanticDriftPullRequest -Drift $drift -Title 't' -Body 'b' -WhatIf
                $r.Opened | Should -BeFalse                          # never opened under -WhatIf
                $r.EditedConcepts | Should -Contain 'account'         # but the edit ran on the clone
                Should -Invoke git -ParameterFilter { $args -contains 'push' } -Times 0
                Should -Invoke gh -Times 0
                # the edit landed in the clone the dry-run left behind for inspection
                $edited = Get-Content -LiteralPath (Join-Path $r.ClonePath 'docs/database/semantic-layer/tables/account.md') -Raw
                $edited | Should -Match '`health_score`'
            }
            finally {
                if ($r -and $r.ClonePath -and (Test-Path $r.ClonePath)) { Remove-Item -Recurse -Force $r.ClonePath -ErrorAction SilentlyContinue }
                if ($saved) { $env:IMPERION_GH_TOKEN = $saved } else { Remove-Item Env:\IMPERION_GH_TOKEN -ErrorAction SilentlyContinue }
            }
        }
    }
}

Describe 'Invoke-ImperionSemanticDriftSync' {
    It 'no-ops cleanly when the bundle path has no tables dir' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog {}
            $missing = Join-Path ([System.IO.Path]::GetTempPath()) ('no-bundle-{0}' -f ([guid]::NewGuid().ToString('N')))
            $r = @(Invoke-ImperionSemanticDriftSync -BundlePath $missing)
            $r.Count | Should -Be 0
            Should -Invoke Write-ImperionLog -ParameterFilter { $Level -eq 'Warn' } -Times 1
        }
    }

    It 'runs detection and a dry-run proposal (opens nothing) when a bundle is present' {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog {}
            Mock Get-ImperionSemanticDrift {
                @([pscustomobject]@{ concept = 'account'; status = 'drift'; added_columns = @('c'); removed_columns = @(); relation = 'account'; doc_timestamp = 't' })
            }
            Mock New-ImperionSemanticDriftProposal { [pscustomobject]@{ Title = 't'; Body = 'b'; Concepts = @('account'); Opened = $false; Url = $null; Mode = 'dry-run' } }

            $bundle = Join-Path ([System.IO.Path]::GetTempPath()) ('bundle-{0}' -f ([guid]::NewGuid().ToString('N')))
            New-Item -ItemType Directory -Force -Path (Join-Path $bundle 'tables') | Out-Null
            try {
                $r = @(Invoke-ImperionSemanticDriftSync -BundlePath $bundle)
                $r.Count | Should -Be 1
                Should -Invoke New-ImperionSemanticDriftProposal -Times 1 -ParameterFilter { -not $Execute }
            }
            finally { Remove-Item -Recurse -Force $bundle }
        }
    }
}
