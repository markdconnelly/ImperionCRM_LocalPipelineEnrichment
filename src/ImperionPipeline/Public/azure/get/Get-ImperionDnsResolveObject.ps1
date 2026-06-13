function Get-ImperionDnsResolveObject {
    <#
    .SYNOPSIS
        Resolve a domain's public DNS posture records and flatten them to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for the PUBLIC ground-truth plane of DNS posture
        (front-end ADR-0063 / migration 0080 + 0081; issue #156). For each domain it resolves
        the posture-relevant records from the public internet (Resolve-ImperionDnsRecord — OS
        resolver with a DNS-over-HTTPS fallback): apex A / TXT (SPF) / MX / NS / CAA, plus
        DMARC (_dmarc TXT) and the common M365 DKIM selector CNAMEs. This is what the world
        sees, and the only signal for domains NOT hosted in Azure DNS (the Azure manage plane
        is the sibling collector Get-ImperionDnsZoneObject, #155).

        Every row is plane 'public', PK (tenant_id, source, external_id). Domains are
        ACCOUNT-scoped (ADR-0063 amendment, #334): the owning account is the isolation key,
        so tenant_id carries the account id for public rows (account_id is also stamped
        explicitly for the silver merge, #157). external_id = '<domain>|public|<type>|<name>'.

        Returns rows; does not write. Requires Initialize-ImperionContext. The task
        (azure/dns-resolve) supplies domains by reading the GUI-managed account_domain list.
    .PARAMETER Domain
        One or more domains to resolve (from the account's account_domain list).
    .PARAMETER AccountId
        The owning account id — stamped on every row (also used as the per-row isolation key).
    .OUTPUTS
        Flat bronze rows (source 'dns', plane 'public') ready for Set-ImperionDnsRecordToBronze.
    .EXAMPLE
        Get-ImperionDnsResolveObject -Domain 'contoso.com' -AccountId $id | Set-ImperionDnsRecordToBronze
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string[]] $Domain,
        [string] $AccountId
    )

    # The isolation owner of a public DNS row is the account (domains are account-scoped).
    $ownerId = if ($AccountId) { $AccountId } else { 'public' }
    $rows = [System.Collections.Generic.List[object]]::new()

    foreach ($domainName in $Domain) {
        # Posture-relevant record plan. DKIM selectors are unknowable in general; probe the
        # common M365 pair (extend via the account_domain note / a selector list later).
        $plan = @(
            @{ Name = $domainName;                              Type = 'A' }
            @{ Name = $domainName;                              Type = 'TXT' }   # SPF + domain verification
            @{ Name = $domainName;                              Type = 'MX' }
            @{ Name = $domainName;                              Type = 'NS' }
            @{ Name = $domainName;                              Type = 'CAA' }
            @{ Name = "_dmarc.$domainName";                     Type = 'TXT' }   # DMARC
            @{ Name = "selector1._domainkey.$domainName";       Type = 'CNAME' } # M365 DKIM
            @{ Name = "selector2._domainkey.$domainName";       Type = 'CNAME' }
        )

        foreach ($item in $plan) {
            $resolved = Resolve-ImperionDnsRecord -Name $item.Name -Type $item.Type
            if ($null -eq $resolved -or [string]::IsNullOrEmpty($resolved.Value)) { continue }

            $source = [pscustomobject]@{
                domain      = $domainName
                plane       = 'public'
                record_type = $item.Type
                name        = $item.Name
                value       = $resolved.Value
                ttl         = $resolved.Ttl
                account_id  = $AccountId
                _xid        = '{0}|public|{1}|{2}' -f $domainName, $item.Type, $item.Name
            }
            $map = [ordered]@{
                domain      = 'domain'
                plane       = 'plane'
                record_type = 'record_type'
                name        = 'name'
                value       = 'value'
                ttl         = { if ($null -ne $resolved.Ttl) { [string]$resolved.Ttl } else { $null } }
                account_id  = { if ($AccountId) { $AccountId } else { $null } }
            }
            $source | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'dns' `
                -TenantId $ownerId -ExternalIdProperty '_xid' | ForEach-Object { $rows.Add($_) }
        }
    }

    Write-ImperionLog -Source 'dns' -Message 'Public DNS records resolved.' -Data @{
        domains = @($Domain).Count; account = $AccountId; rows = $rows.Count
    }
    return $rows.ToArray()
}
