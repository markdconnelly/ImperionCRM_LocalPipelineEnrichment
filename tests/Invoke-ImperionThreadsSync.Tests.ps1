#Requires -Modules Pester
# Hermetic unit tests for Invoke-ImperionThreadsSync (orchestrator) + Resolve-ImperionThreadsToken.
# Asserts the dormant-safe gate, composition, and the registry-resolution path (LocalPipeline #356).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionThreadsSync' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog { }
            Mock New-ImperionDbConnection {
                [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            }
            Mock Get-ImperionThreadsPost { , @([pscustomobject]@{ external_id = 'p1' }) }
            Mock Set-ImperionThreadsPostToBronze { }
            Mock Get-ImperionThreadsReply { }
            Mock Set-ImperionThreadsReplyToBronze { }
            Mock Get-ImperionThreadsMention { }
            Mock Set-ImperionThreadsMentionToBronze { }
            Mock Get-ImperionThreadsInsight { }
            Mock Set-ImperionThreadsInsightToBronze { }
            Mock Invoke-ImperionThreadsMerge { }
        }
    }

    It 'is dormant-safe: no token -> log + no-op, no collectors run' {
        InModuleScope ImperionPipeline {
            Mock Resolve-ImperionThreadsToken { $null }
            Invoke-ImperionThreadsSync
            Should -Invoke Get-ImperionThreadsPost -Times 0
            Should -Invoke Invoke-ImperionThreadsMerge -Times 0
            Should -Invoke Write-ImperionLog -Times 1 -ParameterFilter { $Message -match 'No active company Threads connection' }
        }
    }

    It 'collects posts/replies/mentions/insights then runs the merge when connected' {
        InModuleScope ImperionPipeline {
            Mock Resolve-ImperionThreadsToken { 'tok' }
            Invoke-ImperionThreadsSync
            Should -Invoke Get-ImperionThreadsPost -Times 1
            Should -Invoke Set-ImperionThreadsPostToBronze -Times 1
            Should -Invoke Get-ImperionThreadsReply -Times 1
            Should -Invoke Get-ImperionThreadsMention -Times 1
            Should -Invoke Get-ImperionThreadsInsight -Times 1
            Should -Invoke Invoke-ImperionThreadsMerge -Times 1
        }
    }

    It 'fails closed: a throwing collector logs a warning and never crashes the schedule' {
        InModuleScope ImperionPipeline {
            Mock Resolve-ImperionThreadsToken { 'tok' }
            Mock Get-ImperionThreadsPost { throw 'graph 403' }
            { Invoke-ImperionThreadsSync } | Should -Not -Throw
            Should -Invoke Write-ImperionLog -ParameterFilter { $Level -eq 'Warn' }
        }
    }
}

Describe 'Resolve-ImperionThreadsToken' {
    It 'short-circuits an explicit -Token without hitting the registry' {
        InModuleScope ImperionPipeline {
            Mock Resolve-ImperionCompanyCredential { 'should-not-run' }
            Resolve-ImperionThreadsToken -Token 'explicit' | Should -Be 'explicit'
            Should -Invoke Resolve-ImperionCompanyCredential -Times 0
        }
    }

    It 'resolves the threads provider accessToken field from the company registry' {
        InModuleScope ImperionPipeline {
            Mock Resolve-ImperionCompanyCredential { 'from-kv' }
            Resolve-ImperionThreadsToken | Should -Be 'from-kv'
            Should -Invoke Resolve-ImperionCompanyCredential -Times 1 -ParameterFilter {
                $Provider -eq 'threads' -and $Field -eq 'accessToken'
            }
        }
    }
}
