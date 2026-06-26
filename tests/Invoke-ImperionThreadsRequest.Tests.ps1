#Requires -Modules Pester
# Hermetic unit tests for Invoke-ImperionThreadsRequest. HTTP core mocked in module scope
# (LocalPipeline #356; the Invoke-ImperionMetaRequest precedent).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionThreadsRequest' {
    It 'sends the token as a bearer header against graph.threads.net, never in the querystring' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry { [pscustomobject]@{ Body = [pscustomobject]@{ data = @() } } }
            Invoke-ImperionThreadsRequest -Token 'sekret' -Uri 'me/threads?fields=id' | Out-Null
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter {
                $Headers.Authorization -eq 'Bearer sekret' -and
                $Uri -eq 'https://graph.threads.net/v1.0/me/threads?fields=id' -and
                $Uri -notmatch 'sekret'
            }
        }
    }

    It 'unwraps the { data: [...] } collection shape' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                [pscustomobject]@{ Body = [pscustomobject]@{ data = @(
                            [pscustomobject]@{ id = 'p1' }, [pscustomobject]@{ id = 'p2' }) }
                }
            }
            $items = Invoke-ImperionThreadsRequest -Token 't' -Uri 'me/threads'
            ($items.id -join ',') | Should -Be 'p1,p2'
        }
    }

    It 'yields NOTHING for an empty { data: [] } envelope — never the envelope itself' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry { [pscustomobject]@{ Body = [pscustomobject]@{ data = @() } } }
            $items = @(Invoke-ImperionThreadsRequest -Token 't' -Uri 'me/mentions')
            $items.Count | Should -Be 0
        }
    }

    It 'follows paging.next and STRIPS the embedded access_token from the followed URL' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                if ($Uri -notmatch 'after=') {
                    [pscustomobject]@{ Body = [pscustomobject]@{
                            data   = @([pscustomobject]@{ id = 'p1' })
                            paging = [pscustomobject]@{ next = 'https://graph.threads.net/v1.0/me/threads?access_token=LEAKED&after=cursor1&fields=id' }
                        }
                    }
                }
                else {
                    [pscustomobject]@{ Body = [pscustomobject]@{ data = @([pscustomobject]@{ id = 'p2' }) } }
                }
            }
            $items = Invoke-ImperionThreadsRequest -Token 't' -Uri 'me/threads?fields=id'
            ($items.id -join ',') | Should -Be 'p1,p2'
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter {
                $Uri -match 'after=cursor1' -and $Uri -notmatch 'LEAKED' -and $Uri -notmatch 'access_token'
            }
        }
    }

    It 'honors MaxPages as a hard cap on a runaway cursor' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                [pscustomobject]@{ Body = [pscustomobject]@{
                        data   = @([pscustomobject]@{ id = 'p' })
                        paging = [pscustomobject]@{ next = 'https://graph.threads.net/v1.0/me/threads?after=again' }
                    }
                }
            }
            $items = Invoke-ImperionThreadsRequest -Token 't' -Uri 'me/threads' -MaxPages 3
            $items.Count | Should -Be 3
            Should -Invoke Invoke-ImperionRestWithRetry -Times 3
        }
    }
}
