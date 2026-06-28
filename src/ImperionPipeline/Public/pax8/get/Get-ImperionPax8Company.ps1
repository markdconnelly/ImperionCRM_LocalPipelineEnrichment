function Get-ImperionPax8Company {
    <#
    .SYNOPSIS
        Collect Pax8 customer companies and flatten them to pax8_companies bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for Pax8 (issue #279, epic #1042) — the MSP's
        customer companies under its single distributor account. Pax8 companies are the JOIN
        SPINE for everything below (subscriptions / licenses / orders all carry a company id);
        the merge (#280) resolves each Pax8 company to a silver `account`. Pure procurement /
        billing data: flattens STRAIGHT to Postgres and SKIPS the IT Glue hub (ADR-0006).

        AUTH: Pax8 is an MSP-WIDE COMPANY credential (OAuth2 client-credentials) resolved
        SecretStore-first / Key Vault-fallback by Resolve-ImperionPax8Credential; the connect
        helper Invoke-ImperionPax8Request exchanges it for a short-lived bearer (never logged)
        and owns the page-walk. GATED: until both halves are provisioned (Mark-gated), the
        resolver throws and the scheduled task logs the gap and exits cleanly (idempotent re-run
        converges).

        TARGET: bronze `pax8_companies` (front-end-owned schema, system CLAUDE.md §1 — migration
        0161). tenant_id carries the Pax8 PARTNER/account id (one distributor account spans many
        customer companies; the per-customer key is `pax8_company_id`). external_id = the Pax8
        company `id` (stable) → idempotent upsert. This collector NEVER creates the table; it
        fails loudly if absent (ADR-0005).

        CONFIRM BEFORE LIVE USE: the field names below are modeled from the documented Pax8 API
        but UNVERIFIED against the real account until the credential lands. Each flat column leads
        with the most likely name and keeps a short fallback chain; an unmatched column lands NULL
        and nothing is lost (full payload in raw_payload) — the Datto/KQM precedent.
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant (the Pax8 account).
    .PARAMETER BaseUri
        Pax8 API origin. Default 'https://api.pax8.com'.
    .EXAMPLE
        Get-ImperionPax8Company | Set-ImperionPax8CompanyToBronze
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId,
        [string] $BaseUri = 'https://api.pax8.com'
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.LocalTenantId }
    $cred = Resolve-ImperionPax8Credential

    $companies = Invoke-ImperionPax8Request @cred -Path '/v1/companies' -BaseUri $BaseUri

    $firstOf = {
        param($record, [string[]] $candidates)
        foreach ($candidate in $candidates) {
            $value = Get-ImperionPropertyPath -InputObject $record -Path $candidate
            if ($null -ne $value -and "$value" -ne '') { return $value }
        }
    }

    # Column set mirrors front-end migration 0161 (pax8_companies).
    $map = [ordered]@{
        pax8_company_id = { param($c) & $firstOf $c @('id', 'companyId') }
        name            = { param($c) & $firstOf $c @('name', 'companyName') }
        status          = { param($c) & $firstOf $c @('status', 'state') }
    }

    $companies | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'pax8' -TenantId $TenantId -ExternalIdProperty 'id'
}
