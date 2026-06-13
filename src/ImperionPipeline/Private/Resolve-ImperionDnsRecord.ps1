function Resolve-ImperionDnsRecord {
    <#
    .SYNOPSIS
        Resolve one DNS (name, type) from the public internet, folded to a single value.
    .DESCRIPTION
        Private resolver behind Get-ImperionDnsResolveObject (front-end ADR-0063, public
        ground-truth plane). Tries the OS resolver (Resolve-DnsName) first, falling back to
        DNS-over-HTTPS (dns.google) when that is unavailable (no local resolver, or a
        non-Windows host) — so the collector works off any box and sees what the world sees.
        All records for the (name, type) are folded into one delimited value so the bronze
        row + content_hash are stable; returns $null when nothing resolves (NXDOMAIN / empty).
    .PARAMETER Name
        The DNS name to query (e.g. 'contoso.com', '_dmarc.contoso.com').
    .PARAMETER Type
        The record type (A, AAAA, CNAME, MX, NS, TXT, CAA, ...).
    .OUTPUTS
        [pscustomobject] { Value; Ttl } or $null when nothing resolves.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $Type
    )

    # Fold one resolved record's data to a stable string by type.
    $valueOf = {
        param($r)
        switch ($Type.ToUpperInvariant()) {
            'A'     { return [string](Get-ImperionMember $r 'IPAddress') }
            'AAAA'  { return [string](Get-ImperionMember $r 'IPAddress') }
            'CNAME' { return [string](Get-ImperionMember $r 'NameHost') }
            'NS'    { return [string](Get-ImperionMember $r 'NameHost') }
            'MX'    { return ('{0} {1}' -f (Get-ImperionMember $r 'Preference'), (Get-ImperionMember $r 'NameExchange')).Trim() }
            'TXT'   { return ((@(Get-ImperionMember $r 'Strings')) -join '') }
            default { return [string](Get-ImperionMember $r 'Text') }
        }
    }

    # 1) OS resolver.
    try {
        $answers = Resolve-DnsName -Name $Name -Type $Type -DnsOnly -ErrorAction Stop |
            Where-Object { ([string](Get-ImperionMember $_ 'Type')) -eq $Type }
        $values = @($answers | ForEach-Object { & $valueOf $_ } | Where-Object { $_ })
        if ($values.Count -gt 0) {
            $ttl = ($answers | ForEach-Object { Get-ImperionMember $_ 'TTL' } | Where-Object { $_ } | Select-Object -First 1)
            return [pscustomobject]@{ Value = ($values -join '; '); Ttl = $ttl }
        }
    }
    catch {
        Write-ImperionLog -Level Info -Source 'dns' -Message "OS resolver miss for $Type $Name; trying DoH."
    }

    # 2) DNS-over-HTTPS fallback (dns.google JSON API).
    try {
        $doh = Invoke-ImperionRestWithRetry -Method GET `
            -Uri ("https://dns.google/resolve?name={0}&type={1}" -f [uri]::EscapeDataString($Name), $Type) `
            -Headers @{ Accept = 'application/dns-json' }
        $records = @(Get-ImperionMember $doh.Body 'Answer')
        $values = @($records | ForEach-Object { ([string](Get-ImperionMember $_ 'data')).Trim('"') } | Where-Object { $_ })
        if ($values.Count -gt 0) {
            $ttl = ($records | ForEach-Object { Get-ImperionMember $_ 'TTL' } | Where-Object { $_ } | Select-Object -First 1)
            return [pscustomobject]@{ Value = ($values -join '; '); Ttl = $ttl }
        }
    }
    catch {
        Write-ImperionLog -Level Warn -Source 'dns' -Message "DoH resolve failed for $Type ${Name}: $($_.Exception.Message)"
    }

    return $null
}
