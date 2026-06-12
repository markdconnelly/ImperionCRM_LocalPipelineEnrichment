#Requires -Modules Pester
# Hermetic unit tests for Invoke-ImperionPlaudRequest (MCP JSON-RPC tools/call). HTTP mocked.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionPlaudRequest' {
    It 'POSTs a JSON-RPC tools/call with the bearer token and returns structuredContent' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                [pscustomobject]@{ Body = [pscustomobject]@{
                    jsonrpc = '2.0'; id = 'x'
                    result = [pscustomobject]@{ structuredContent = [pscustomobject]@{ files = @([pscustomobject]@{ id = 'f1' }) } }
                } }
            }
            $result = Invoke-ImperionPlaudRequest -AccessToken 'tok' -Tool 'list_files'
            @($result.files).Count | Should -Be 1
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter {
                $Method -eq 'POST' -and $Headers.Authorization -eq 'Bearer tok' -and
                ($Body | ConvertFrom-Json).method -eq 'tools/call' -and
                ($Body | ConvertFrom-Json).params.name -eq 'list_files'
            }
        }
    }

    It 'parses a text content block as JSON when no structuredContent exists' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                [pscustomobject]@{ Body = [pscustomobject]@{
                    result = [pscustomobject]@{ content = @([pscustomobject]@{ type = 'text'; text = '{"summary":"Quarterly sync"}' }) }
                } }
            }
            (Invoke-ImperionPlaudRequest -AccessToken 't' -Tool 'get_note' -Arguments @{ file_id = 'f1' }).summary | Should -Be 'Quarterly sync'
        }
    }

    It 'throws loudly on a JSON-RPC error (auth expiry surfaces to the task gate)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                [pscustomobject]@{ Body = [pscustomobject]@{ error = [pscustomobject]@{ code = -32001; message = 'unauthorized' } } }
            }
            { Invoke-ImperionPlaudRequest -AccessToken 'stale' -Tool 'list_files' } | Should -Throw '*unauthorized*'
        }
    }
}
