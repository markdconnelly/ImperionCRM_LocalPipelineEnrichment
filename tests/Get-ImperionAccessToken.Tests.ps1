#Requires -Modules Pester
# Hermetic tests for Get-ImperionAccessToken. Get-MsalToken is stubbed/mocked in module
# scope. The fake certificate must be a REAL in-memory X509Certificate2 (with a private
# key): when MSAL.PS is installed, Get-MsalToken's typed -ClientCertificate parameter
# binds BEFORE the Pester mock body runs, so a PSCustomObject stand-in fails binding.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
    InModuleScope ImperionPipeline {
        if (-not (Get-Command Get-MsalToken -ErrorAction SilentlyContinue)) {
            function script:Get-MsalToken { param($ClientId, $TenantId, $ClientCertificate, $ClientSecret, $Scopes) }
        }
        # Ephemeral self-signed cert, never touches a cert store; HasPrivateKey = $true.
        $rsa = [System.Security.Cryptography.RSA]::Create(2048)
        $request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
            'CN=ImperionPipeline-Test', $rsa,
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
        $script:ImperionTestCertificate = $request.CreateSelfSigned(
            [datetimeoffset]::Now.AddDays(-1), [datetimeoffset]::Now.AddDays(1))
    }
}

Describe 'Get-ImperionAccessToken' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            $script:ImperionTokenCache = @{}
            Mock Get-Item { $script:ImperionTestCertificate }
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

    It 'mints via the client SECRET without touching the certificate store (ADR-0103)' {
        InModuleScope ImperionPipeline {
            Mock Get-Item { throw 'cert store must not be read for secret auth' }
            $sec = [securestring]::new()   # content irrelevant — Get-MsalToken is mocked
            $t = Get-ImperionAccessToken -Resource 'r-secret' -TenantId 't-secret' -ClientId 'c1' -ClientSecret $sec
            $t | Should -Be 'tok-abc'
            Should -Invoke Get-MsalToken -Times 1 -ParameterFilter { $null -ne $ClientSecret }
            Should -Invoke Get-Item -Times 0
        }
    }
}
