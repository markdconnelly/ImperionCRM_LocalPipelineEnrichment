function Get-ImperionEasyDmarcDomain {
    <#
    .SYNOPSIS
        Collect EasyDMARC domains + DMARC/SPF/DKIM/BIMI posture and flatten to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for EasyDMARC, Imperion's 3rd-party DNS/DMARC
        provider (issue #122). Pure security-posture data about a client `account` and its
        domains: it flattens STRAIGHT to Postgres bronze and SKIPS the IT Glue hub (domain
        health is operational truth the AI agent reasons over, not an IT Glue documented
        object — same call as the KQM/DocuSign sources). Returns rows; does not write.
        Requires Initialize-ImperionContext.

        TARGET (PROPOSED bronze shape — schema is owned by the front-end repo per the
        cross-repo contract, system CLAUDE.md §1; this collector is authored against the
        bronze migration proposed in ImperionCRM issue #581, ADR-0039 per-source
        envelope, PK (tenant_id, source, external_id)): bronze `easydmarc_domains` →
        silver domain/DMARC posture. external_id = the domain name.

        AUTH: EasyDMARC is a COMPANY credential (Imperion's MSP account) resolved
        SecretStore-first / Key Vault-fallback by Resolve-ImperionEasyDmarcApiKey and sent
        as an Authorization: Bearer header (URLs are NOT secret-bearing). GATED: until the
        key is provisioned (Mark-gated; plan must include API access), the resolver throws
        and the scheduled task logs the gap and exits cleanly (idempotent re-run converges).

        CONFIRM BEFORE LIVE USE: base URL, the /domains path, the pagination scheme, and the
        field names below are ASSUMPTIONS from the public docs (no live key yet — issue #122).
        Each flat column leads with the most likely name and keeps a short fallback chain;
        an unmatched column lands NULL and nothing is lost (full payload in raw_payload).
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant. (Live tenant
        mapping comes from the EasyDMARC Organizations endpoint group — a follow-up once the
        org→client mapping is verified against a live key; see docs/integrations/easydmarc.md.)
    .PARAMETER BaseUri
        EasyDMARC API base. Default 'https://api.easydmarc.com' (placeholder — confirm).
    .PARAMETER ApiKey
        EasyDMARC API key override. Defaults to the SecretStore/Key Vault resolution.
    .EXAMPLE
        Get-ImperionEasyDmarcDomain | Set-ImperionEasyDmarcDomainToBronze
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId,
        [string] $BaseUri = 'https://api.easydmarc.com',
        [string] $ApiKey
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.LocalTenantId }
    $ApiKey = Resolve-ImperionEasyDmarcApiKey -ApiKey $ApiKey

    $uri = '{0}/domains' -f $BaseUri.TrimEnd('/')
    $domains = Invoke-ImperionEasyDmarcRequest -ApiKey $ApiKey -Uri $uri

    # First non-null of a chain of plausible source names (StrictMode-safe via Get-ImperionMember).
    $firstOf = {
        param($record, [string[]] $candidates)
        foreach ($candidate in $candidates) {
            $value = Get-ImperionMember $record $candidate
            if ($null -ne $value -and "$value" -ne '') { return $value }
        }
    }

    $map = [ordered]@{
        domain           = { param($d) & $firstOf $d @('name', 'domain', 'domainName') }
        organization_ref = { param($d) & $firstOf $d @('organization_id', 'organizationId', 'organization_ref') }
        setup_status     = { param($d) & $firstOf $d @('setup_status', 'setupStatus', 'status') }
        dmarc_policy     = { param($d) & $firstOf $d @('dmarc_policy', 'dmarcPolicy', 'policy') }
        dmarc_status     = { param($d) & $firstOf $d @('dmarc_status', 'dmarcStatus') }
        spf_status       = { param($d) & $firstOf $d @('spf_status', 'spfStatus') }
        dkim_status      = { param($d) & $firstOf $d @('dkim_status', 'dkimStatus') }
        bimi_status      = { param($d) & $firstOf $d @('bimi_status', 'bimiStatus') }
    }

    $domains | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'easydmarc' -TenantId $TenantId -ExternalIdProperty 'name'
}
