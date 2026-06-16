function Get-ImperionAmazonBusinessOrder {
    <#
    .SYNOPSIS
        Collect Amazon Business orders + shipment/tracking + spend and flatten to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for Amazon Business, one of Imperion's procurement
        sources (issue #198, ADR-0021). Pure logistics/procurement data — orders, shipment/tracking,
        and spend lines: it flattens STRAIGHT to Postgres bronze and SKIPS the IT Glue hub (ADR-0006
        — procurement spend is a BI signal the agent reasons over, not an IT Glue documented object;
        the same call as the QBO finance sources). Returns rows; does not write. Requires
        Initialize-ImperionContext.

        TARGET: bronze `amazon_business_orders` (front-end-owned schema, ADR-0042 / ADR-0005 —
        front-end migration 0120, front-end #688; lossless envelope, PK (tenant_id, source,
        external_id)). external_id = the Amazon Business order id. Per-line procurement detail
        (items, qty, unit price) and the full carrier/tracking detail stay lossless in raw_payload;
        the flat columns carry the curated, server-queryable subset (order header + spend + a single
        primary tracking).

        AUTH: Amazon Business is a COMPANY credential (Imperion's own purchasing account) resolved
        SecretStore-first / Key Vault-fallback by Resolve-ImperionAmazonBusinessToken and sent as an
        Authorization: Bearer header (URLs are NOT secret-bearing). GATED: until the token is
        provisioned (Mark-gated; plan must include API access), the resolver throws and the scheduled
        task logs the gap and exits cleanly (idempotent re-run converges).

        CONFIRM BEFORE LIVE USE: base URL, the /orders path, the cursor pagination scheme, and the
        field names below are ASSUMPTIONS from the public docs (no live credential yet — issue #198).
        Each flat column leads with the most likely name and keeps a short fallback chain; an
        unmatched column lands NULL and nothing is lost (full payload in raw_payload).
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant (Amazon Business is the
        MSP's own purchasing account, not per-customer credentialed).
    .PARAMETER BaseUri
        Amazon Business API base. Default 'https://na.business-api.amazon.com' (placeholder — confirm).
    .PARAMETER Token
        Amazon Business access token override. Defaults to the SecretStore/Key Vault resolution.
    .EXAMPLE
        Get-ImperionAmazonBusinessOrder | Set-ImperionAmazonBusinessOrderToBronze
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId,
        [string] $BaseUri = 'https://na.business-api.amazon.com',
        [string] $Token
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }
    $Token = Resolve-ImperionAmazonBusinessToken -Token $Token

    $uri = '{0}/orders/v1/orders' -f $BaseUri.TrimEnd('/')
    $orders = Invoke-ImperionAmazonBusinessRequest -AccessToken $Token -Uri $uri

    # First non-null of a chain of plausible source names/paths (StrictMode-safe).
    $firstOf = {
        param($record, [string[]] $candidates)
        foreach ($candidate in $candidates) {
            $value = Get-ImperionPropertyPath -InputObject $record -Path $candidate
            if ($null -ne $value -and "$value" -ne '') { return $value }
        }
    }

    # Column set mirrors front-end migration 0120 (amazon_business_orders). order_total carries spend.
    $map = [ordered]@{
        order_id           = { param($o) & $firstOf $o @('orderId', 'order_id', 'id') }
        order_date         = { param($o) & $firstOf $o @('orderDate', 'order_date', 'purchaseDate') }
        order_status       = { param($o) & $firstOf $o @('orderStatus', 'order_status', 'status') }
        order_total        = { param($o) & $firstOf $o @('orderTotal.amount', 'orderTotal', 'order_total', 'total') }
        currency           = { param($o) & $firstOf $o @('orderTotal.currencyCode', 'currency', 'currencyCode') }
        buyer_name         = { param($o) & $firstOf $o @('buyerInfo.name', 'buyerName', 'buyer_name', 'buyer') }
        tracking_number    = { param($o) & $firstOf $o @('shipment.trackingNumber', 'trackingNumber', 'tracking_number') }
        carrier            = { param($o) & $firstOf $o @('shipment.carrier', 'carrier', 'carrierName') }
        ship_status        = { param($o) & $firstOf $o @('shipment.status', 'shipStatus', 'ship_status', 'shipmentStatus') }
        estimated_delivery = { param($o) & $firstOf $o @('shipment.estimatedDeliveryDate', 'estimatedDelivery', 'estimated_delivery') }
    }

    $orders | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'amazon_business' -TenantId $TenantId -ExternalIdProperty 'orderId'
}
