#Requires -Modules Pester
# Hermetic unit tests for Connect-ImperionDarkWebId. HTTP core mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Connect-ImperionDarkWebId' {
    BeforeEach {
        InModuleScope ImperionPipeline { $script:ImperionDarkWebIdTokenCache = @{} }
    }

    It 'posts a client_credentials grant and returns the access token' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                [pscustomobject]@{ Body = [pscustomobject]@{ access_token = 'dwid-abc'; expires_in = 3600 } }
            }
            $tok = Connect-ImperionDarkWebId -ClientId 'cid' -ClientSecret 'sec' -TokenEndpoint 'https://auth.example/token' -Force
            $tok | Should -Be 'dwid-abc'
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter {
                $Method -eq 'POST' -and $Body.grant_type -eq 'client_credentials' -and $Body.client_id -eq 'cid'
            }
        }
    }

    It 'caches the token so a second call does not re-request' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                [pscustomobject]@{ Body = [pscustomobject]@{ access_token = 't'; expires_in = 3600 } }
            }
            Connect-ImperionDarkWebId -ClientId 'c' -ClientSecret 's' -TokenEndpoint 'https://auth/token' | Out-Null
            Connect-ImperionDarkWebId -ClientId 'c' -ClientSecret 's' -TokenEndpoint 'https://auth/token' | Out-Null
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1
        }
    }

    It 'includes the scope in the grant when supplied' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry {
                [pscustomobject]@{ Body = [pscustomobject]@{ access_token = 't'; expires_in = 60 } }
            }
            Connect-ImperionDarkWebId -ClientId 'c' -ClientSecret 's' -TokenEndpoint 'https://auth/token' -Scope 'monitoring.read' -Force | Out-Null
            Should -Invoke Invoke-ImperionRestWithRetry -Times 1 -ParameterFilter { $Body.scope -eq 'monitoring.read' }
        }
    }

    It 'throws when the endpoint returns no access_token' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionRestWithRetry { [pscustomobject]@{ Body = [pscustomobject]@{ error = 'invalid_client' } } }
            { Connect-ImperionDarkWebId -ClientId 'c' -ClientSecret 's' -TokenEndpoint 'https://auth/token' -Force } |
                Should -Throw '*no access_token*'
        }
    }
}
