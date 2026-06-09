#Requires -Modules Pester
# Unit tests for the private Get-ImperionAutotaskContext (Autotask auth headers + zone).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionAutotaskContext' {
    It 'maps the secret names to Autotask auth headers and resolves the zone' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionSecretNames { @{ AutotaskUserName = 'autotask-username'; AutotaskIntegrationCode = 'autotask-integration-code'; AutotaskSecret = 'autotask-secret' } }
            Mock Get-ImperionSecretValue { param($Name) "val:$Name" }
            Mock Get-ImperionAutotaskZone { 'https://ws.autotask.net/atservicesrest/V1.0' }

            $ctx = Get-ImperionAutotaskContext
            $ctx.ApiBase                      | Should -Be 'https://ws.autotask.net/atservicesrest/V1.0'
            $ctx.Headers.UserName             | Should -Be 'val:autotask-username'
            $ctx.Headers.ApiIntegrationCode   | Should -Be 'val:autotask-integration-code'
            $ctx.Headers.Secret               | Should -Be 'val:autotask-secret'
            $ctx.Headers.'Content-Type'       | Should -Be 'application/json'
            Should -Invoke Get-ImperionAutotaskZone -Times 1 -ParameterFilter { $UserName -eq 'val:autotask-username' }
        }
    }
}
