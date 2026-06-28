function Get-ImperionCdwOrder {
    <#
    .SYNOPSIS
        Collect CDW orders + shipment/tracking + spend lines and flatten to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for CDW, one of Imperion's procurement sources (issue
        #198, ADR-0021). Pure logistics/procurement data — orders, shipment/tracking, and spend
        lines: it flattens STRAIGHT to Postgres bronze and SKIPS the IT Glue hub (ADR-0006 —
        procurement spend is a BI signal the agent reasons over, not an IT Glue documented object;
        the same call as the QBO finance + Amazon Business sources). Returns rows; does not write.
        Requires Initialize-ImperionContext.

        TARGET: bronze `cdw_orders` (front-end-owned schema, ADR-0042 / ADR-0005 — front-end
        migration 0120, front-end #688; lossless envelope, PK (tenant_id, source, external_id)).
        external_id = the CDW order number. Per-line procurement detail (SKUs, qty, unit price) and
        the full carrier/tracking detail stay lossless in raw_payload; the flat columns carry the
        curated, server-queryable subset (order header + PO + spend + a single primary tracking).

        AUTH: CDW is a COMPANY credential (Imperion's own purchasing account) resolved
        SecretStore-first / Key Vault-fallback by Resolve-ImperionCdwApiKey and sent as an
        Authorization: Bearer header (URLs are NOT secret-bearing). GATED: until the key is
        provisioned (Mark-gated; plan must include API access), the resolver throws and the scheduled
        task logs the gap and exits cleanly (idempotent re-run converges).

        CONFIRM BEFORE LIVE USE: base URL, the /orders path, the page pagination scheme, and the
        field names below are ASSUMPTIONS from the public docs (no live key yet — issue #198). Each
        flat column leads with the most likely name and keeps a short fallback chain; an unmatched
        column lands NULL and nothing is lost (full payload in raw_payload).
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant (CDW is the MSP's own
        purchasing account, not per-customer credentialed).
    .PARAMETER BaseUri
        CDW API base. Default 'https://api.cdw.com' (placeholder — confirm).
    .PARAMETER ApiKey
        CDW API key override. Defaults to the SecretStore/Key Vault resolution.
    .EXAMPLE
        Get-ImperionCdwOrder | Set-ImperionCdwOrderToBronze
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId,
        [string] $BaseUri = 'https://api.cdw.com',
        [string] $ApiKey
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.LocalTenantId }
    $ApiKey = Resolve-ImperionCdwApiKey -ApiKey $ApiKey

    $uri = '{0}/orders/v1/orders' -f $BaseUri.TrimEnd('/')
    $orders = Invoke-ImperionCdwRequest -ApiKey $ApiKey -Uri $uri

    # First non-null of a chain of plausible source names/paths (StrictMode-safe).
    $firstOf = {
        param($record, [string[]] $candidates)
        foreach ($candidate in $candidates) {
            $value = Get-ImperionPropertyPath -InputObject $record -Path $candidate
            if ($null -ne $value -and "$value" -ne '') { return $value }
        }
    }

    # Column set mirrors front-end migration 0120 (cdw_orders). order_total carries spend.
    $map = [ordered]@{
        order_id           = { param($o) & $firstOf $o @('orderNumber', 'orderId', 'order_id', 'id') }
        po_number          = { param($o) & $firstOf $o @('poNumber', 'po_number', 'purchaseOrderNumber') }
        order_date         = { param($o) & $firstOf $o @('orderDate', 'order_date', 'createdDate') }
        order_status       = { param($o) & $firstOf $o @('orderStatus', 'order_status', 'status') }
        order_total        = { param($o) & $firstOf $o @('orderTotal.amount', 'orderTotal', 'order_total', 'total') }
        currency           = { param($o) & $firstOf $o @('orderTotal.currencyCode', 'currency', 'currencyCode') }
        account_ref        = { param($o) & $firstOf $o @('accountId', 'account_ref', 'accountNumber', 'customerNumber') }
        tracking_number    = { param($o) & $firstOf $o @('shipment.trackingNumber', 'trackingNumber', 'tracking_number') }
        carrier            = { param($o) & $firstOf $o @('shipment.carrier', 'carrier', 'carrierName') }
        ship_status        = { param($o) & $firstOf $o @('shipment.status', 'shipStatus', 'ship_status', 'shipmentStatus') }
        estimated_delivery = { param($o) & $firstOf $o @('shipment.estimatedDeliveryDate', 'estimatedDelivery', 'estimated_delivery') }
    }

    $orders | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'cdw' -TenantId $TenantId -ExternalIdProperty 'orderNumber'
}
