#Requires -Modules Pester
# Hermetic tests for Set-ImperionITGlueFlexibleAsset: the IT Glue request layer is mocked.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionITGlueFlexibleAsset' {
    It 'updates (PATCH) an existing asset matched by the key trait' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionITGlueRequest {
                param($Path, $ApiKey, $Method = 'GET', $Body, $Query, $BaseUri)
                if ($Path -eq 'flexible_asset_types') { return , @([pscustomobject]@{ id = '5'; attributes = [pscustomobject]@{ name = 'Azure Service Principal' } }) }
                if ($Path -eq 'flexible_assets' -and $Method -eq 'GET') { return , @([pscustomobject]@{ id = '99'; attributes = [pscustomobject]@{ traits = [pscustomobject]@{ 'app-id' = 'app1' } } }) }
                if ($Path -like 'flexible_assets/*') { return [pscustomobject]@{ data = [pscustomobject]@{ id = '99' } } }
                return [pscustomobject]@{ data = [pscustomobject]@{ id = 'should-not-create' } }
            }
            $id = Set-ImperionITGlueFlexibleAsset -ApiKey 'k' -TypeName 'Azure Service Principal' -OrganizationId 42 -MatchTrait 'app-id' -MatchValue 'app1' -Traits @{ 'app-id' = 'app1' }
            $id | Should -Be '99'
            Should -Invoke Invoke-ImperionITGlueRequest -ParameterFilter { $Method -eq 'PATCH' } -Times 1
        }
    }

    It 'does not throw and creates (POST) when an existing asset lacks the match trait' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionITGlueRequest {
                param($Path, $ApiKey, $Method = 'GET', $Body, $Query, $BaseUri)
                if ($Path -eq 'flexible_asset_types') { return , @([pscustomobject]@{ id = '5'; attributes = [pscustomobject]@{ name = 'Azure Service Principal' } }) }
                if ($Path -eq 'flexible_assets' -and $Method -eq 'GET') { return , @([pscustomobject]@{ id = '98'; attributes = [pscustomobject]@{ traits = [pscustomobject]@{ 'other-trait' = 'x' } } }) }  # NO app-id
                return [pscustomobject]@{ data = [pscustomobject]@{ id = 'created-new' } }
            }
            # A throw on the absent match trait would fail this test (the StrictMode regression guard).
            $id = Set-ImperionITGlueFlexibleAsset -ApiKey 'k' -TypeName 'Azure Service Principal' -OrganizationId 42 -MatchTrait 'app-id' -MatchValue 'app1' -Traits @{ 'app-id' = 'app1' }
            $id | Should -Be 'created-new'
            Should -Invoke Invoke-ImperionITGlueRequest -ParameterFilter { $Method -eq 'POST' } -Times 1
        }
    }

    It 'throws when the type is missing and -CreateTypeIfMissing is not set' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionITGlueRequest {
                param($Path, $ApiKey, $Method = 'GET', $Body, $Query, $BaseUri)
                return , @()   # no types found
            }
            { Set-ImperionITGlueFlexibleAsset -ApiKey 'k' -TypeName 'Missing Type' -OrganizationId 42 -MatchTrait 'app-id' -MatchValue 'app1' -Traits @{ } } |
                Should -Throw '*not found*'
        }
    }
}
