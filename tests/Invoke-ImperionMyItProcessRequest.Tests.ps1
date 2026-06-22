#Requires -Modules Pester
# Hermetic unit tests for Invoke-ImperionMyItProcessRequest. HTTP core mocked in module scope.
# Pins the live-verified contract (issue #297): mitp-api-key header, { ..., totalCount, items }
# wrapper, and totalCount-driven paging that does NOT stop early when the server pages small.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionMyItProcessRequest' {
    It 'sends the mitp-api-key header (NOT the querystring) and unwraps the items collection' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                [pscustomobject]@{ Body = [pscustomobject]@{ totalCount = 1; items = @([pscustomobject]@{ id = 'r1' }) } }
            }
            $rows = Invoke-ImperionMyItProcessRequest -ApiKey 'tok' -Uri 'https://reporting.live.myitprocess.com/public-api/v1/recommendations'
            $rows[0].id | Should -Be 'r1'
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter {
                $Headers['mitp-api-key'] -eq 'tok' -and $Uri -notmatch 'mitp-api-key'
            }
        }
    }

    It 'pages by totalCount, accumulating until the accumulated count reaches totalCount' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                if ($Uri -match 'page=1\b') {
                    [pscustomobject]@{ Body = [pscustomobject]@{ totalCount = 3; items = @([pscustomobject]@{ id = 'a' }, [pscustomobject]@{ id = 'b' }) } }
                }
                else {
                    [pscustomobject]@{ Body = [pscustomobject]@{ totalCount = 3; items = @([pscustomobject]@{ id = 'c' }) } }
                }
            }
            $rows = Invoke-ImperionMyItProcessRequest -ApiKey 'tok' -Uri 'https://reporting.live.myitprocess.com/public-api/v1/recommendations'
            ($rows.id -join ',') | Should -Be 'a,b,c'
            Should -Invoke Invoke-ImperionRestWithRetry -Times 2
        }
    }

    It 'does NOT stop early when the server pages smaller than -PageSize (the #297 regression)' {
        InModuleScope ImperionPipeline {
            # Server returns one item per page; totalCount=3. A short-page heuristic with the
            # default PageSize=100 would stop after page 1 and drop b,c. totalCount must win.
            Mock Invoke-ImperionRestWithRetry {
                $n = if ($Uri -match 'page=(\d+)') { [int]$Matches[1] } else { 1 }
                $id = @('a', 'b', 'c')[$n - 1]
                [pscustomobject]@{ Body = [pscustomobject]@{ totalCount = 3; items = @([pscustomobject]@{ id = $id }) } }
            }
            $rows = Invoke-ImperionMyItProcessRequest -ApiKey 'tok' -Uri 'https://reporting.live.myitprocess.com/public-api/v1/recommendations'
            ($rows.id -join ',') | Should -Be 'a,b,c'
            Should -Invoke Invoke-ImperionRestWithRetry -Times 3
        }
    }

    It 'falls back to the short-page heuristic when no totalCount is present' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                if ($Uri -match 'page=1\b') {
                    [pscustomobject]@{ Body = [pscustomobject]@{ items = @([pscustomobject]@{ id = 'a' }, [pscustomobject]@{ id = 'b' }) } }
                }
                else {
                    [pscustomobject]@{ Body = [pscustomobject]@{ items = @([pscustomobject]@{ id = 'c' }) } }
                }
            }
            $rows = Invoke-ImperionMyItProcessRequest -ApiKey 'tok' -Uri 'https://reporting.live.myitprocess.com/public-api/v1/recommendations' -PageSize 2
            ($rows.id -join ',') | Should -Be 'a,b,c'
            Should -Invoke Invoke-ImperionRestWithRetry -Times 2
        }
    }

    It 'tolerates a bare array body (StrictMode-safe)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry { [pscustomobject]@{ Body = @([pscustomobject]@{ id = 'z' }) } }
            $rows = Invoke-ImperionMyItProcessRequest -ApiKey 'tok' -Uri 'https://reporting.live.myitprocess.com/public-api/v1/recommendations' -PageSize 5
            $rows[0].id | Should -Be 'z'
        }
    }
}
