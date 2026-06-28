function Get-ImperionPax8Subscription {
    <#
    .SYNOPSIS
        Collect Pax8 subscriptions and flatten them to pax8_subscriptions bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for Pax8 (issue #279, epic #1042) — the recurring
        license commitments per customer company: the BILLING SPINE the agreement cost-recon
        (#1041) reconciles against contracted counts. Pure procurement / billing data: flattens
        STRAIGHT to Postgres and SKIPS the IT Glue hub (ADR-0006).

        AUTH: an MSP-WIDE COMPANY credential (OAuth2 client-credentials) resolved by
        Resolve-ImperionPax8Credential; the connect helper Invoke-ImperionPax8Request owns the
        bearer exchange + page-walk. GATED: the resolver throws until provisioned (Mark-gated) and
        the scheduled task logs the gap + exits cleanly (idempotent re-run converges).

        TARGET: bronze `pax8_subscriptions` (front-end migration 0161). tenant_id = the Pax8
        partner/account id; the per-customer key is `company_id`. external_id = the Pax8
        subscription `id` (stable) → idempotent upsert. NEVER creates the table; fails loudly if
        absent (ADR-0005).

        CONFIRM BEFORE LIVE USE: the field names below are modeled from the documented Pax8 API
        but UNVERIFIED until the credential lands; unmatched columns land NULL and the full payload
        survives in raw_payload (the Datto/KQM precedent).
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant (the Pax8 account).
    .PARAMETER BaseUri
        Pax8 API origin. Default 'https://api.pax8.com'.
    .EXAMPLE
        Get-ImperionPax8Subscription | Set-ImperionPax8SubscriptionToBronze
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

    $subscriptions = Invoke-ImperionPax8Request @cred -Path '/v1/subscriptions' -BaseUri $BaseUri

    $firstOf = {
        param($record, [string[]] $candidates)
        foreach ($candidate in $candidates) {
            $value = Get-ImperionPropertyPath -InputObject $record -Path $candidate
            if ($null -ne $value -and "$value" -ne '') { return $value }
        }
    }

    # Column set mirrors front-end migration 0161 (pax8_subscriptions).
    $map = [ordered]@{
        pax8_subscription_id = { param($s) & $firstOf $s @('id', 'subscriptionId') }
        company_id           = { param($s) & $firstOf $s @('companyId', 'company.id') }
        product_id           = { param($s) & $firstOf $s @('productId', 'product.id') }
        product_name         = { param($s) & $firstOf $s @('productName', 'product.name', 'name') }
        quantity             = { param($s) & $firstOf $s @('quantity', 'seats', 'units') }
        status               = { param($s) & $firstOf $s @('status', 'state') }
        billing_term         = { param($s) & $firstOf $s @('billingTerm', 'billing.term', 'term') }
        start_date           = { param($s) & $firstOf $s @('startDate', 'createdDate', 'createdAt') }
    }

    $subscriptions | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'pax8' -TenantId $TenantId -ExternalIdProperty 'id'
}
