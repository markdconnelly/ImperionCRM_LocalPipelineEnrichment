#Requires -Modules Pester
# Hermetic tests for Get-ImperionTelivyReport: secrets + Telivy request mocked.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionTelivyReport' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'partner' } }
            Mock Get-ImperionSecretNames { @{ TelivyApiKey = 'Telivy-API-Key' } }
            Mock Get-ImperionSecretValue { 'telivy-key' }
        }
    }

    It 'flattens reports to the bronze envelope with source televy' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionTelivyRequest {
                , @([pscustomobject]@{ id = 'r1'; title = 'Acme Risk'; accountName = 'Acme'; dimension = 'email'; reportUrl = 'https://t/r1'; score = 78 })
            }
            $rows = Get-ImperionTelivyReport
            $rows[0].title        | Should -Be 'Acme Risk'
            $rows[0].account_name | Should -Be 'Acme'
            $rows[0].score        | Should -Be '78'
            $rows[0].source       | Should -Be 'televy'
            $rows[0].external_id  | Should -Be 'r1'
        }
    }

    It 'does not throw when a report omits optional fields' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionTelivyRequest { , @([pscustomobject]@{ id = 'r2'; title = 'Bare' }) }
            { Get-ImperionTelivyReport } | Should -Not -Throw
        }
    }

    It 'sends the Telivy api key and reports path to the connect layer' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionTelivyRequest { , @() }
            Get-ImperionTelivyReport | Out-Null
            Should -Invoke Invoke-ImperionTelivyRequest -Times 1 -ParameterFilter { $ApiKey -eq 'telivy-key' -and $Uri -like '*/reports?*' }
        }
    }
}
