#Requires -Modules Pester
# Hermetic test for Invoke-ImperionServicePrincipalSync: Graph + DB mocked in module scope.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionServicePrincipalSync' {
    It 'does not throw on a service principal that omits optional collections' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 't1' } }
            Mock Get-ImperionSecretNames { @{ ITGlueWriteKey = 'itglue-write-api-key' } }
            Mock Get-ImperionGraphToken { 'token' }
            Mock New-ImperionDbConnection { [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { } }
            Mock Write-ImperionLog { }
            $captured = $null
            Mock Invoke-ImperionBronzeUpsert { $script:captured = $Rows; [pscustomobject]@{ scanned = 1; inserted = 1; updated = 0; unchanged = 0 } }
            Mock Invoke-ImperionGraphRequest {
                , @([pscustomobject]@{ id = 'sp1'; appId = 'app1'; displayName = 'Bare SP' })   # no replyUrls/tags/appRoles/keyCredentials/...
            }
            { Invoke-ImperionServicePrincipalSync -SkipITGlue } | Should -Not -Throw
            $row = $script:captured[0]
            $row.app_roles_count       | Should -Be 0
            $row.key_credentials_count | Should -Be 0
            $row.reply_urls            | Should -BeNullOrEmpty
        }
    }

    It 'computes the nearest credential expiry when keyCredentials are present' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 't1' } }
            Mock Get-ImperionSecretNames { @{ ITGlueWriteKey = 'itglue-write-api-key' } }
            Mock Get-ImperionGraphToken { 'token' }
            Mock New-ImperionDbConnection { [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { } }
            Mock Write-ImperionLog { }
            Mock Invoke-ImperionBronzeUpsert { $script:captured2 = $Rows; [pscustomobject]@{ scanned = 1; inserted = 1; updated = 0; unchanged = 0 } }
            Mock Invoke-ImperionGraphRequest {
                , @([pscustomobject]@{ id = 'sp2'; appId = 'app2'; displayName = 'SP'; keyCredentials = @(
                            [pscustomobject]@{ endDateTime = '2027-01-01T00:00:00Z' },
                            [pscustomobject]@{ endDateTime = '2026-07-01T00:00:00Z' }
                        ) })
            }
            Invoke-ImperionServicePrincipalSync -SkipITGlue
            $script:captured2[0].key_credentials_count | Should -Be 2
            $script:captured2[0].key_credential_next_expiry | Should -Match '2026-07-01'
        }
    }
}
