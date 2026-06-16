#Requires -Modules Pester
# Hermetic unit tests for Invoke-ImperionDattoRmmRequest. HTTP core mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionDattoRmmRequest' {
    It 'exchanges the API key for a bearer, then GETs devices with that bearer' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                if ($Method -eq 'POST') {
                    [pscustomobject]@{ Body = [pscustomobject]@{ access_token = 'bearer-xyz'; expires_in = 3600 } }
                }
                else {
                    [pscustomobject]@{ Body = [pscustomobject]@{ pageDetails = [pscustomobject]@{ nextPageUrl = $null }; devices = @([pscustomobject]@{ uid = 'd1' }) } }
                }
            }
            $rows = Invoke-ImperionDattoRmmRequest -ApiKey 'key' -Path '/v2/account/devices' -EntityProperty 'devices'
            $rows.Count | Should -Be 1
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter { $Method -eq 'POST' -and $Uri -match '/auth/oauth/token' }
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter { $Method -eq 'GET' -and $Headers.Authorization -eq 'Bearer bearer-xyz' }
        }
    }

    It 'throws when the token exchange returns no access_token (fail loud)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry { [pscustomobject]@{ Body = [pscustomobject]@{ error = 'invalid_client' } } }
            { Invoke-ImperionDattoRmmRequest -ApiKey 'key' -Path '/v2/account/devices' -EntityProperty 'devices' } |
                Should -Throw '*no access_token*'
        }
    }

    It 'follows pageDetails.nextPageUrl until it is null' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                if ($Method -eq 'POST') { return [pscustomobject]@{ Body = [pscustomobject]@{ access_token = 't' } } }
                if ($Uri -match 'page=2') {
                    [pscustomobject]@{ Body = [pscustomobject]@{ pageDetails = [pscustomobject]@{ nextPageUrl = $null }; devices = @([pscustomobject]@{ uid = 'd3' }) } }
                }
                else {
                    [pscustomobject]@{ Body = [pscustomobject]@{ pageDetails = [pscustomobject]@{ nextPageUrl = 'https://api.datto-rmm.com/v2/account/devices?page=2' }; devices = @([pscustomobject]@{ uid = 'd1' }, [pscustomobject]@{ uid = 'd2' }) } }
                }
            }
            $rows = Invoke-ImperionDattoRmmRequest -ApiKey 'key' -Path '/v2/account/devices' -EntityProperty 'devices'
            ($rows.uid -join ',') | Should -Be 'd1,d2,d3'
            Should -Invoke Invoke-ImperionRestWithRetry -Times 2 -ParameterFilter { $Method -eq 'GET' }
        }
    }

    It 'tolerates a bare array body (pending live-shape verification)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                if ($Method -eq 'POST') { return [pscustomobject]@{ Body = [pscustomobject]@{ access_token = 't' } } }
                [pscustomobject]@{ Body = @([pscustomobject]@{ uid = 'bare' }) }
            }
            $rows = Invoke-ImperionDattoRmmRequest -ApiKey 'key' -Path '/v2/account/devices' -EntityProperty 'devices'
            $rows[0].uid | Should -Be 'bare'
        }
    }
}
