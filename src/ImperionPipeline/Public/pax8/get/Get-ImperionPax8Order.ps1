function Get-ImperionPax8Order {
    <#
    .SYNOPSIS
        Collect Pax8 orders and flatten them to pax8_orders bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for Pax8 (issue #279, epic #1042) — the procurement
        events: the PROCURE side of the procure→provision→bill loop (#1042). Pure procurement /
        billing data: flattens STRAIGHT to Postgres and SKIPS the IT Glue hub (ADR-0006).

        AUTH: an MSP-WIDE COMPANY credential (OAuth2 client-credentials) resolved by
        Resolve-ImperionPax8Credential; Invoke-ImperionPax8Request owns the bearer exchange +
        page-walk. GATED: the resolver throws until provisioned (Mark-gated) and the scheduled
        task logs the gap + exits cleanly (idempotent re-run converges).

        TARGET: bronze `pax8_orders` (front-end migration 0161). tenant_id = the Pax8
        partner/account id; per-customer key is `company_id`. external_id = the Pax8 order `id`
        (stable) → idempotent upsert. The order `total` is stored as a currency string (true value
        in raw_payload). NEVER creates the table; fails loudly if absent (ADR-0005).

        CONFIRM BEFORE LIVE USE: field names are modeled from the documented Pax8 API but
        UNVERIFIED until the credential lands; unmatched columns land NULL and the full payload
        survives in raw_payload (the Datto/KQM precedent).
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant (the Pax8 account).
    .PARAMETER BaseUri
        Pax8 API origin. Default 'https://api.pax8.com'.
    .EXAMPLE
        Get-ImperionPax8Order | Set-ImperionPax8OrderToBronze
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId,
        [string] $BaseUri = 'https://api.pax8.com'
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }
    $cred = Resolve-ImperionPax8Credential

    $orders = Invoke-ImperionPax8Request @cred -Path '/v1/orders' -BaseUri $BaseUri

    $firstOf = {
        param($record, [string[]] $candidates)
        foreach ($candidate in $candidates) {
            $value = Get-ImperionPropertyPath -InputObject $record -Path $candidate
            if ($null -ne $value -and "$value" -ne '') { return $value }
        }
    }

    # Column set mirrors front-end migration 0161 (pax8_orders).
    $map = [ordered]@{
        pax8_order_id = { param($o) & $firstOf $o @('id', 'orderId') }
        company_id    = { param($o) & $firstOf $o @('companyId', 'company.id') }
        status        = { param($o) & $firstOf $o @('status', 'state') }
        ordered_at    = { param($o) & $firstOf $o @('orderedDate', 'createdDate', 'createdAt', 'placedAt') }
        total         = { param($o) & $firstOf $o @('total', 'totalAmount', 'amount') }
    }

    $orders | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'pax8' -TenantId $TenantId -ExternalIdProperty 'id'
}
