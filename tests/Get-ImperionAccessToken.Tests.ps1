#Requires -Modules Pester
# Hermetic tests for Get-ImperionAccessToken. Get-MsalToken (MSAL.PS, not installed here) is
# stubbed in module scope so it can be mocked; Get-Item is mocked to return a fake certificate.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
    InModuleScope ImperionPipeline {
        if (-not (Get-Command Get-MsalToken -ErrorAction SilentlyContinue)) {
            function script:Get-MsalToken { param($ClientId, $TenantId, $ClientCertificate, $Scopes) }
        }
    }
}

Describe 'Get-ImperionAccessToken' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            $script:ImperionTokenCache = @{}
            Mock Get-Item { [pscustomobject]@{ HasPrivateKey = $true } }
            Mock Get-MsalToken { [pscustomobject]@{ AccessToken = 'tok-abc'; ExpiresOn = [datetimeoffset]::Now.AddHours(1) } }
        }
    }

    It 'acquires a token and returns its access token' {
        InModuleScope ImperionPipeline {
            $t = Get-ImperionAccessToken -Resource 'https://graph.microsoft.com/.default' -TenantId 't1' -ClientId 'c1' -CertThumbprint 'ABC'
            $t | Should -Be 'tok-abc'
            Should -Invoke Get-MsalToken -Times 1
        }
    }

    It 'caches per (tenant, resource) so a second call does not re-acquire' {
        InModuleScope ImperionPipeline {
            Get-ImperionAccessToken -Resource 'r' -TenantId 't1' -ClientId 'c1' -CertThumbprint 'ABC' | Out-Null
            Get-ImperionAccessToken -Resource 'r' -TenantId 't1' -ClientId 'c1' -CertThumbprint 'ABC' | Out-Null
            Should -Invoke Get-MsalToken -Times 1
        }
    }

    It 'acquires separately for a different tenant or resource' {
        InModuleScope ImperionPipeline {
            Get-ImperionAccessToken -Resource 'r' -TenantId 't1' -ClientId 'c1' -CertThumbprint 'ABC' | Out-Null
            Get-ImperionAccessToken -Resource 'r' -TenantId 't2' -ClientId 'c1' -CertThumbprint 'ABC' | Out-Null
            Should -Invoke Get-MsalToken -Times 2
        }
    }

    It 're-acquires when the cached token is near expiry' {
        InModuleScope ImperionPipeline {
            $script:ImperionTokenCache['t1|r'] = [pscustomobject]@{ AccessToken = 'old'; ExpiresOn = (Get-Date).AddMinutes(1) }  # < 5 min
            $t = Get-ImperionAccessToken -Resource 'r' -TenantId 't1' -ClientId 'c1' -CertThumbprint 'ABC'
            $t | Should -Be 'tok-abc'
            Should -Invoke Get-MsalToken -Times 1
        }
    }

    It 'throws when the certificate has no accessible private key' {
        InModuleScope ImperionPipeline {
            Mock Get-Item { [pscustomobject]@{ HasPrivateKey = $false } }
            { Get-ImperionAccessToken -Resource 'r' -TenantId 't1' -ClientId 'c1' -CertThumbprint 'ABC' } | Should -Throw '*private key*'
        }
    }
}
