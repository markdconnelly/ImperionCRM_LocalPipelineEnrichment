#Requires -Modules Pester
# Hermetic unit tests for Invoke-ImperionMetaRequest. HTTP core mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionMetaRequest' {
    It 'sends the token as a bearer header, never in the querystring' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry { [pscustomobject]@{ Body = [pscustomobject]@{ data = @() } } }
            Invoke-ImperionMetaRequest -Token 'sekret' -Uri '123/posts?fields=message' | Out-Null
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter {
                $Headers.Authorization -eq 'Bearer sekret' -and
                $Uri -eq 'https://graph.facebook.com/v23.0/123/posts?fields=message' -and
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
            $items = Invoke-ImperionMetaRequest -Token 't' -Uri '123/posts'
            ($items.id -join ',') | Should -Be 'p1,p2'
        }
    }

    It 'yields NOTHING for an empty { data: [] } envelope — never the envelope itself (#133)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                [pscustomobject]@{ Body = [pscustomobject]@{ data = @() } }
            }
            $items = @(Invoke-ImperionMetaRequest -Token 't' -Uri '123_456/comments')
            $items.Count | Should -Be 0
        }
    }

    It 'tolerates a bare single resource (no data wrapper)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                [pscustomobject]@{ Body = [pscustomobject]@{ id = '123'; access_token = 'pt' } }
            }
            $items = @(Invoke-ImperionMetaRequest -Token 't' -Uri '123?fields=access_token')
            $items.Count | Should -Be 1
            $items[0].access_token | Should -Be 'pt'
        }
    }

    It 'follows paging.next and STRIPS the embedded access_token from the followed URL' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                if ($Uri -notmatch 'after=') {
                    [pscustomobject]@{ Body = [pscustomobject]@{
                            data   = @([pscustomobject]@{ id = 'p1' })
                            paging = [pscustomobject]@{ next = 'https://graph.facebook.com/v23.0/123/posts?access_token=LEAKED&after=cursor1&fields=message' }
                        }
                    }
                }
                else {
                    [pscustomobject]@{ Body = [pscustomobject]@{ data = @([pscustomobject]@{ id = 'p2' }) } }
                }
            }
            $items = Invoke-ImperionMetaRequest -Token 't' -Uri '123/posts?fields=message'
            ($items.id -join ',') | Should -Be 'p1,p2'
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter {
                $Uri -match 'after=cursor1' -and $Uri -notmatch 'LEAKED' -and $Uri -notmatch 'access_token'
            }
        }
    }

    It 're-pins the version segment when Meta rewrites paging.next to a newer version (#135)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                if ($Uri -notmatch 'after=') {
                    [pscustomobject]@{ Body = [pscustomobject]@{
                            data   = @([pscustomobject]@{ id = 'p1' })
                            paging = [pscustomobject]@{ next = 'https://graph.facebook.com/v25.0/123/posts?access_token=LEAKED&after=cursor1' }
                        }
                    }
                }
                else {
                    [pscustomobject]@{ Body = [pscustomobject]@{ data = @([pscustomobject]@{ id = 'p2' }) } }
                }
            }
            Invoke-ImperionMetaRequest -Token 't' -Uri '123/posts' | Out-Null
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter {
                $Uri -match '/v23\.0/123/posts' -and $Uri -notmatch '/v25\.0/' -and $Uri -match 'after=cursor1'
            }
        }
    }

    It 'stops when paging.next is absent' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                [pscustomobject]@{ Body = [pscustomobject]@{ data = @([pscustomobject]@{ id = 'p1' }) } }
            }
            Invoke-ImperionMetaRequest -Token 't' -Uri '123/posts' | Out-Null
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1
        }
    }

    It 'honors MaxPages as a hard cap on a runaway cursor' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                [pscustomobject]@{ Body = [pscustomobject]@{
                        data   = @([pscustomobject]@{ id = 'p' })
                        paging = [pscustomobject]@{ next = 'https://graph.facebook.com/v23.0/123/posts?after=again' }
                    }
                }
            }
            $items = Invoke-ImperionMetaRequest -Token 't' -Uri '123/posts' -MaxPages 3
            $items.Count | Should -Be 3
            Should -Invoke Invoke-ImperionRestWithRetry -Times 3
        }
    }
}
