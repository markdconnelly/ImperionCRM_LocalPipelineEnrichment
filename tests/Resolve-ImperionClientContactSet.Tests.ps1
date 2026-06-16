#Requires -Modules Pester
# Hermetic tests for the silver client-contact set resolver (DB query mocked; no live DB).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Resolve-ImperionClientContactSet' {
    It 'builds case-insensitive email + domain sets from silver contacts' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery {
                @(
                    [pscustomobject]@{ email = 'sam@acme.com' },
                    [pscustomobject]@{ email = 'CFO@Globex.com' }
                )
            }
            $conn = [pscustomobject]@{}
            $result = Resolve-ImperionClientContactSet -Connection $conn
            $result.Emails.Contains('SAM@ACME.COM') | Should -BeTrue   # case-insensitive
            $result.Emails.Contains('cfo@globex.com') | Should -BeTrue
            $result.Domains.Contains('acme.com') | Should -BeTrue
            $result.Domains.Contains('GLOBEX.COM') | Should -BeTrue    # case-insensitive
        }
    }

    It 'skips blank / non-email rows without throwing' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery {
                @(
                    [pscustomobject]@{ email = '' },
                    [pscustomobject]@{ email = 'not-an-email' },
                    [pscustomobject]@{ email = 'good@client.com' }
                )
            }
            $result = Resolve-ImperionClientContactSet -Connection ([pscustomobject]@{})
            $result.Emails.Count | Should -Be 1
            $result.Emails.Contains('good@client.com') | Should -BeTrue
        }
    }

    It 'returns empty sets when there are no client contacts (dormant)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { @() }
            $result = Resolve-ImperionClientContactSet -Connection ([pscustomobject]@{})
            $result.Emails.Count | Should -Be 0
            $result.Domains.Count | Should -Be 0
        }
    }
}
