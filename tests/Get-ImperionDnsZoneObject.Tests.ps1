#Requires -Modules Pester
# Hermetic tests for Get-ImperionDnsZoneObject: ARM token + requests mocked, routed by path
# (zone list / per-zone recordsets / per-zone Authorization permissions).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionDnsZoneObject' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'partner' } }
            Mock Get-ImperionArmToken { 'arm-token' }
            Mock Write-ImperionLog {}
            # writable permissions by default (grants the recordset write)
            Mock Invoke-ImperionArmRequest {
                switch -Regex ($Path) {
                    '/permissions' {
                        return @([pscustomobject]@{ actions = @('Microsoft.Network/dnsZones/*'); notActions = @() })
                    }
                    '/recordsets' {
                        return @(
                            [pscustomobject]@{ name = '@'; type = 'Microsoft.Network/dnszones/TXT'
                                properties = [pscustomobject]@{ TTL = 3600; TXTRecords = @([pscustomobject]@{ value = @('v=spf1 include:spf.protection.outlook.com -all') }) } }
                            [pscustomobject]@{ name = 'www'; type = 'Microsoft.Network/dnszones/CNAME'
                                properties = [pscustomobject]@{ TTL = 300; CNAMERecord = [pscustomobject]@{ cname = 'contoso.azurewebsites.net' } } }
                        )
                    }
                    'Microsoft.Network/dnsZones\?' {
                        return @([pscustomobject]@{
                                id = '/subscriptions/sub-1/resourceGroups/rg-dns/providers/Microsoft.Network/dnszones/contoso.com'
                                name = 'contoso.com'
                                properties = [pscustomobject]@{ nameServers = @('ns1-01.azure-dns.com', 'ns2-01.azure-dns.net') }
                            })
                    }
                    default { return @() }
                }
            }
        }
    }

    It 'emits a zone row stamped with entity + the standard envelope, verdict managed when writable' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionDnsZoneObject -SubscriptionId 'sub-1')
            $zone = $rows | Where-Object { $_.entity -eq 'zones' }
            $zone.Count        | Should -Be 1
            $zone.domain       | Should -Be 'contoso.com'
            $zone.in_azure     | Should -Be 'true'
            $zone.manageable   | Should -Be 'true'
            $zone.verdict      | Should -Be 'managed'
            $zone.resource_group | Should -Be 'rg-dns'
            $zone.ns_records   | Should -Be 'ns1-01.azure-dns.com; ns2-01.azure-dns.net'
            $zone.source       | Should -Be 'dns'
            $zone.tenant_id    | Should -Be 'partner'
            $zone.content_hash | Should -Match '^[0-9a-f]{64}$'
        }
    }

    It 'emits azure-plane record rows with composite external_id + flattened value' {
        InModuleScope ImperionPipeline {
            $records = @(Get-ImperionDnsZoneObject -SubscriptionId 'sub-1') | Where-Object { $_.entity -eq 'records' }
            $records.Count | Should -Be 2

            $spf = $records | Where-Object { $_.record_type -eq 'TXT' }
            $spf.plane       | Should -Be 'azure'
            $spf.name        | Should -Be '@'
            $spf.value       | Should -Be 'v=spf1 include:spf.protection.outlook.com -all'
            $spf.ttl         | Should -Be '3600'
            $spf.external_id | Should -Be 'contoso.com|azure|TXT|@'

            $cname = $records | Where-Object { $_.record_type -eq 'CNAME' }
            $cname.value | Should -Be 'contoso.azurewebsites.net'
        }
    }

    It 'verdict in-azure-readonly when the identity cannot write recordsets' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionArmRequest {
                switch -Regex ($Path) {
                    '/permissions' { return @([pscustomobject]@{ actions = @('*/read'); notActions = @() }) }
                    '/recordsets'  { return @() }
                    'Microsoft.Network/dnsZones\?' {
                        return @([pscustomobject]@{
                                id = '/subscriptions/sub-1/resourceGroups/rg-dns/providers/Microsoft.Network/dnszones/legacy.com'
                                name = 'legacy.com'; properties = [pscustomobject]@{ nameServers = @('ns1.azure-dns.com') } })
                    }
                    default { return @() }
                }
            }
            $zone = @(Get-ImperionDnsZoneObject -SubscriptionId 'sub-1') | Where-Object { $_.entity -eq 'zones' }
            $zone.manageable | Should -Be 'false'
            $zone.verdict    | Should -Be 'in-azure-readonly'
        }
    }

    It 'notActions that revoke the write downgrade manageable to false' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionArmRequest {
                switch -Regex ($Path) {
                    '/permissions' { return @([pscustomobject]@{ actions = @('*'); notActions = @('Microsoft.Network/dnsZones/recordSets/write') }) }
                    '/recordsets'  { return @() }
                    'Microsoft.Network/dnsZones\?' {
                        return @([pscustomobject]@{
                                id = '/subscriptions/sub-1/resourceGroups/rg/providers/Microsoft.Network/dnszones/x.com'
                                name = 'x.com'; properties = [pscustomobject]@{ nameServers = @() } })
                    }
                    default { return @() }
                }
            }
            $zone = @(Get-ImperionDnsZoneObject -SubscriptionId 'sub-1') | Where-Object { $_.entity -eq 'zones' }
            $zone.manageable | Should -Be 'false'
        }
    }

    It 'skips a zone with an empty id without aborting the sync (#323)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionArmRequest {
                switch -Regex ($Path) {
                    '/permissions' { return @([pscustomobject]@{ actions = @('Microsoft.Network/dnsZones/*'); notActions = @() }) }
                    '/recordsets'  { return @() }
                    'Microsoft.Network/dnsZones\?' {
                        return @(
                            [pscustomobject]@{ id = ''; name = 'broken.com'; properties = [pscustomobject]@{ nameServers = @() } }
                            [pscustomobject]@{ id = '/subscriptions/sub-1/resourceGroups/rg/providers/Microsoft.Network/dnszones/good.com'
                                name = 'good.com'; properties = [pscustomobject]@{ nameServers = @('ns1.azure-dns.com') } }
                        )
                    }
                    default { return @() }
                }
            }
            # The empty-id zone used to throw on the mandatory -Scope bind and abort the run;
            # if the guard regresses this call throws and fails the test.
            $rows = @(Get-ImperionDnsZoneObject -SubscriptionId 'sub-1')
            $zones = @($rows | Where-Object { $_.entity -eq 'zones' })
            $zones.Count  | Should -Be 1
            $zones[0].domain | Should -Be 'good.com'
            Should -Invoke Write-ImperionLog -ParameterFilter { $Level -eq 'Warn' -and $Message -match 'empty id' }
        }
    }

    It 'authenticates against the requested tenant' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionArmRequest { , @() }
            Get-ImperionDnsZoneObject -SubscriptionId 'sub-1' -TenantId 'customer-9' | Out-Null
            Should -Invoke Get-ImperionArmToken -Times 1 -ParameterFilter { $TenantId -eq 'customer-9' }
        }
    }
}
