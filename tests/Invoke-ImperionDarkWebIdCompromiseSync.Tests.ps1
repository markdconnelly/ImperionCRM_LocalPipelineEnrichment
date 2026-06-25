#Requires -Modules Pester
# Hermetic tests for Invoke-ImperionDarkWebIdCompromiseSync. Credential resolver, collector, and
# bronze writer are mocked — no live Dark Web ID / DB / Key Vault. Pins the registry resolution of
# the Basic-auth {username, password} blob (ADR-0103) and the domain-scoping branch.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionDarkWebIdCompromiseSync' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Resolve-ImperionCompanyCredential {
                if ($Field -eq 'username') { 'dwid-user' } else { 'dwid-pass' }
            }
            Mock Get-ImperionDarkWebIdCompromise { @() }
            Mock Set-ImperionDarkWebIdCompromiseToBronze {}
            $env:IMPERION_DARKWEBID_DOMAIN = $null
        }
    }

    AfterEach {
        $env:IMPERION_DARKWEBID_DOMAIN = $null
    }

    It 'resolves username AND password from the company credential registry (fail-closed) and never reads the raw secret' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionKeyVaultSecret { throw 'raw KV read must not be used' }
            Invoke-ImperionDarkWebIdCompromiseSync
            Should -Invoke Resolve-ImperionCompanyCredential -Times 1 -ParameterFilter {
                $Provider -eq 'darkwebid' -and $Field -eq 'username' -and $FailClosed
            }
            Should -Invoke Resolve-ImperionCompanyCredential -Times 1 -ParameterFilter {
                $Provider -eq 'darkwebid' -and $Field -eq 'password' -and $FailClosed
            }
            Should -Invoke Get-ImperionKeyVaultSecret -Times 0
        }
    }

    It 'threads the resolved Basic-auth credentials into the collector (all-domains branch)' {
        InModuleScope ImperionPipeline {
            Invoke-ImperionDarkWebIdCompromiseSync
            Should -Invoke Get-ImperionDarkWebIdCompromise -Times 1 -ParameterFilter {
                $Username -eq 'dwid-user' -and $Password -eq 'dwid-pass' -and -not $Domain
            }
        }
    }

    It 'scopes to one domain when IMPERION_DARKWEBID_DOMAIN is set' {
        InModuleScope ImperionPipeline {
            $env:IMPERION_DARKWEBID_DOMAIN = 'acme.com'
            Invoke-ImperionDarkWebIdCompromiseSync
            Should -Invoke Get-ImperionDarkWebIdCompromise -Times 1 -ParameterFilter {
                $Username -eq 'dwid-user' -and $Password -eq 'dwid-pass' -and $Domain -eq 'acme.com'
            }
        }
    }
}
