#Requires -Modules Pester
# Hermetic tests for Get-ImperionDnsResolveObject: the resolver boundary
# (Resolve-ImperionDnsRecord) is mocked, routed by (name, type).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionDnsResolveObject' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog {}
            Mock Resolve-ImperionDnsRecord {
                # Return canned posture records; selector2 + CAA intentionally absent (no record).
                if ($Type -eq 'TXT' -and $Name -like '_dmarc.*') {
                    return [pscustomobject]@{ Value = 'v=DMARC1; p=reject; rua=mailto:dmarc@contoso.com'; Ttl = 3600 }
                }
                if ($Type -eq 'TXT') { return [pscustomobject]@{ Value = 'v=spf1 include:spf.protection.outlook.com -all'; Ttl = 3600 } }
                if ($Type -eq 'MX')  { return [pscustomobject]@{ Value = '0 contoso-com.mail.protection.outlook.com'; Ttl = 3600 } }
                if ($Type -eq 'NS')  { return [pscustomobject]@{ Value = 'ns1-01.azure-dns.com; ns2-01.azure-dns.net'; Ttl = 86400 } }
                if ($Type -eq 'A')   { return [pscustomobject]@{ Value = '20.1.2.3'; Ttl = 300 } }
                if ($Type -eq 'CNAME' -and $Name -like 'selector1.*') {
                    return [pscustomobject]@{ Value = 'selector1-contoso-com._domainkey.contoso.onmicrosoft.com'; Ttl = 3600 }
                }
                return $null   # selector2, CAA -> no record
            }
        }
    }

    It 'emits public-plane rows with composite external_id, account stamping, and the envelope' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionDnsResolveObject -Domain 'contoso.com' -AccountId 'acc-1')
            # SPF/TXT, DMARC, MX, NS, A, selector1 CNAME = 6 records (selector2 + CAA absent)
            $rows.Count | Should -Be 6
            $rows | ForEach-Object { $_.plane | Should -Be 'public' }
            $rows | ForEach-Object { $_.account_id | Should -Be 'acc-1' }
            $rows | ForEach-Object { $_.tenant_id  | Should -Be 'acc-1' }   # account is the isolation owner
            $rows | ForEach-Object { $_.source     | Should -Be 'dns' }
            $rows | ForEach-Object { $_.content_hash | Should -Match '^[0-9a-f]{64}$' }
        }
    }

    It 'distinguishes SPF, DMARC and DKIM by name; external_id carries domain|public|type|name' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionDnsResolveObject -Domain 'contoso.com' -AccountId 'acc-1')

            $spf = $rows | Where-Object { $_.record_type -eq 'TXT' -and $_.name -eq 'contoso.com' }
            $spf.value       | Should -Be 'v=spf1 include:spf.protection.outlook.com -all'
            $spf.external_id | Should -Be 'contoso.com|public|TXT|contoso.com'

            $dmarc = $rows | Where-Object { $_.name -eq '_dmarc.contoso.com' }
            $dmarc.value       | Should -Match '^v=DMARC1'
            $dmarc.external_id | Should -Be 'contoso.com|public|TXT|_dmarc.contoso.com'

            $dkim = $rows | Where-Object { $_.name -like 'selector1.*' }
            $dkim.record_type  | Should -Be 'CNAME'
            $dkim.external_id  | Should -Be 'contoso.com|public|CNAME|selector1._domainkey.contoso.com'
        }
    }

    It 'resolves every domain in the list' {
        InModuleScope ImperionPipeline {
            Get-ImperionDnsResolveObject -Domain @('a.com', 'b.com') -AccountId 'acc-1' | Out-Null
            Should -Invoke Resolve-ImperionDnsRecord -ParameterFilter { $Name -like '*a.com' } -Times 1 -Scope It -Exactly:$false
            Should -Invoke Resolve-ImperionDnsRecord -ParameterFilter { $Name -like '*b.com' } -Times 1 -Scope It -Exactly:$false
        }
    }

    It 'falls back to a public-owner key when no account is supplied' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionDnsResolveObject -Domain 'contoso.com')
            ($rows | Select-Object -First 1).tenant_id  | Should -Be 'public'
            ($rows | Select-Object -First 1).account_id | Should -BeNullOrEmpty
        }
    }
}
