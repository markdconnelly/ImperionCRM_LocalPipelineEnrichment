#Requires -Modules Pester
# Hermetic tests for Remove-ImperionStorageBlob (issue #169). The HTTP core, the storage
# token, and config are mocked in module scope so the idempotent-404 contract, the URL/auth
# shape, and WhatIf are observable with no network and no Azure.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Remove-ImperionStorageBlob' {
    It 'returns $true on a 2xx delete and sends a bearer token + DELETE to the blob URL' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'tid'; ClientId = 'cid'; CertThumbprint = 'th'; Storage = @{ AccountName = 'acct'; ReceiptContainer = 'receipts' } } }
            Mock Get-ImperionStorageToken { 'tok' }
            Mock Invoke-ImperionHttp { [pscustomobject]@{ Body = $null; Status = 202; Headers = @{} } }

            Remove-ImperionStorageBlob -BlobPath '2026/01/a.pdf' | Should -BeTrue
            Should -Invoke Invoke-ImperionHttp -Times 1 -ParameterFilter {
                $Method -eq 'DELETE' -and
                $Uri -eq 'https://acct.blob.core.windows.net/receipts/2026/01/a.pdf' -and
                $Headers.Authorization -eq 'Bearer tok'
            }
        }
    }

    It 'treats a 404 (already deleted) as an idempotent no-op and returns $false' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'tid'; ClientId = 'cid'; CertThumbprint = 'th'; Storage = @{ AccountName = 'acct'; ReceiptContainer = 'receipts' } } }
            Mock Get-ImperionStorageToken { 'tok' }
            Mock Invoke-ImperionHttp { [pscustomobject]@{ Body = $null; Status = 404; Headers = @{} } }

            Remove-ImperionStorageBlob -BlobPath 'x.pdf' | Should -BeFalse
        }
    }

    It 'throws on an unexpected status' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'tid'; ClientId = 'cid'; CertThumbprint = 'th'; Storage = @{ AccountName = 'acct'; ReceiptContainer = 'receipts' } } }
            Mock Get-ImperionStorageToken { 'tok' }
            Mock Invoke-ImperionHttp { [pscustomobject]@{ Body = $null; Status = 500; Headers = @{} } }

            { Remove-ImperionStorageBlob -BlobPath 'x.pdf' } | Should -Throw
        }
    }

    It 'strips a leading container prefix so the URL never doubles the container segment' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'tid'; ClientId = 'cid'; CertThumbprint = 'th'; Storage = @{ AccountName = 'acct'; ReceiptContainer = 'receipts' } } }
            Mock Get-ImperionStorageToken { 'tok' }
            Mock Invoke-ImperionHttp { [pscustomobject]@{ Body = $null; Status = 202; Headers = @{} } }

            Remove-ImperionStorageBlob -BlobPath 'receipts/2026/01/a.pdf' | Out-Null
            Should -Invoke Invoke-ImperionHttp -Times 1 -ParameterFilter {
                $Uri -eq 'https://acct.blob.core.windows.net/receipts/2026/01/a.pdf'
            }
        }
    }

    It 'WhatIf returns without minting a token or issuing the DELETE' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'tid'; ClientId = 'cid'; CertThumbprint = 'th'; Storage = @{ AccountName = 'acct'; ReceiptContainer = 'receipts' } } }
            Mock Get-ImperionStorageToken { 'tok' }
            Mock Invoke-ImperionHttp { [pscustomobject]@{ Body = $null; Status = 202; Headers = @{} } }

            Remove-ImperionStorageBlob -BlobPath 'x.pdf' -WhatIf | Should -BeFalse
            Should -Invoke Invoke-ImperionHttp -Times 0
            Should -Invoke Get-ImperionStorageToken -Times 0
        }
    }
}
