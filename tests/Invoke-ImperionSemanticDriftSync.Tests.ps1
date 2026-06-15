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
                Should -Invoke Write-ImperionLog -ParameterFilter { $Level -eq 'Warn' } -Times 1
            }
            finally { if ($saved) { $env:IMPERION_GH_TOKEN = $saved } }
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
            Mock New-ImperionSemanticDriftProposal { [pscustomobject]@{ Title = 't'; Body = 'b'; Concepts = @('account'); Opened = $false } }

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
