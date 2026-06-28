#Requires -Modules Pester
# Hermetic tests for Get-ImperionSharePointSite: Graph token + requests mocked.
# Scope guard: the collector may ONLY call /sites/getAllSites — never /drives or /items.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionSharePointSite' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'partner' } }
            Mock Get-ImperionGraphToken { 'graph-token' }
            Mock Write-ImperionLog {}
            Mock Invoke-ImperionGraphRequest {
                @(
                    [pscustomobject]@{
                        id = 'imperionllc.sharepoint.com,coll-guid-1,web-guid-1'
                        displayName = 'Imperion Operations'; name = 'operations'
                        webUrl = 'https://imperionllc.sharepoint.com/sites/operations'
                        description = 'Internal ops hub'
                        createdDateTime = '2024-01-15T10:00:00Z'
                        lastModifiedDateTime = '2026-06-11T22:15:00Z'
                        isPersonalSite = $false
                        siteCollection = [pscustomobject]@{ hostname = 'imperionllc.sharepoint.com' }
                    }
                    [pscustomobject]@{
                        id = 'imperionllc-my.sharepoint.com,coll-guid-2,web-guid-2'
                        displayName = 'Mark Connelly'; name = 'markconnelly'
                        webUrl = 'https://imperionllc-my.sharepoint.com/personal/mark'
                        isPersonalSite = $true
                        siteCollection = [pscustomobject]@{ hostname = 'imperionllc-my.sharepoint.com' }
                    }
                )
            }
        }
    }

    It 'flattens the site enumeration to the 0078 columns + standard envelope' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionSharePointSite)
            $rows.Count | Should -Be 2

            $site = $rows | Where-Object { $_.external_id -eq 'imperionllc.sharepoint.com,coll-guid-1,web-guid-1' }
            $site.display_name             | Should -Be 'Imperion Operations'
            $site.name                     | Should -Be 'operations'
            $site.web_url                  | Should -Be 'https://imperionllc.sharepoint.com/sites/operations'
            $site.description              | Should -Be 'Internal ops hub'
            $site.is_personal_site         | Should -Be 'false'
            $site.site_collection_hostname | Should -Be 'imperionllc.sharepoint.com'
            $site.storage_used_bytes       | Should -BeNullOrEmpty   # not exposed on /sites -> NULL, never fetched from a drive
            $site.storage_quota_bytes      | Should -BeNullOrEmpty
            $site.source       | Should -Be 'm365'
            $site.tenant_id    | Should -Be 'partner'
            $site.content_hash | Should -Match '^[0-9a-f]{64}$'
            $site.raw_payload  | Should -Match 'sharepoint\.com'
        }
    }

    It 'keys external_id on the Graph composite site id and flags personal sites (all-text bronze)' {
        InModuleScope ImperionPipeline {
            $personal = @(Get-ImperionSharePointSite) | Where-Object { $_.is_personal_site -eq 'true' }
            $personal.external_id      | Should -Be 'imperionllc-my.sharepoint.com,coll-guid-2,web-guid-2'
            $personal.is_personal_site | Should -BeOfType [string]
        }
    }

    It 'calls ONLY the getAllSites enumeration - never a drive, item, or content endpoint' {
        InModuleScope ImperionPipeline {
            Get-ImperionSharePointSite | Out-Null
            Should -Invoke Invoke-ImperionGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://graph.microsoft.com/v1.0/sites/getAllSites'
            }
            # Scope guard (Mark 2026-06-12: Files.Read.All pruned - site inventory only).
            Should -Invoke Invoke-ImperionGraphRequest -Times 0 -ParameterFilter {
                $Uri -match '/drives?\b|/items\b|/content\b'
            }
        }
    }

    It 'does not throw when records omit optional fields' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest { @([pscustomobject]@{ id = 'bare' }) }
            { Get-ImperionSharePointSite } | Should -Not -Throw
        }
    }

    It 'collects from the requested tenant' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionGraphRequest { , @() }
            Get-ImperionSharePointSite -TenantId 'customer-9' | Out-Null
            Should -Invoke Get-ImperionGraphToken -Times 1 -ParameterFilter { $TenantId -eq 'customer-9' }
        }
    }
}
