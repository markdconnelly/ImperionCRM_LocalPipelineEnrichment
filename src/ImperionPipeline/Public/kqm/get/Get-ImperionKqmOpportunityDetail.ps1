function Get-ImperionKqmOpportunityDetail {
    <#
    .SYNOPSIS
        Collect the KQM won-quote DETAIL (sections / lines / sales orders / sales-order lines)
        and flatten each to its bronze shape, scoped to a won-quote id set.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for Kaseya Quote Manager, the follow-up to the
        header collector Get-ImperionKqmOpportunity (issue #160). Pure CRM/sales data:
        flattens straight to Postgres and SKIPS the IT Glue hub. Returns ONE object with four
        flat-row sets (Sections / Lines / SalesOrders / SalesOrderLines); does not write —
        Set-ImperionKqmOpportunityDetailToBronze persists them. Requires Initialize-ImperionContext.

        WHY ONE COLLECTOR, NOT FOUR (issue #161): the detail endpoints are NOT server-filterable
        by quote (`?quoteID=` is ignored → the full collection comes back), so silver value is a
        client-side join. The join chain is interdependent —
        `quoteline.quoteSectionID → quotesection.id → quotesection.quoteID → quote.id` and
        `salesorderline.salesOrderID → salesorder.id → salesorder.quoteID → quote.id` — so the
        won-section and won-salesorder id sets discovered here must flow into the line filters.
        Keeping that one chain in a single collector avoids re-pulling or threading id sets
        through the task, and lets it be tested as one unit.

        BOUND COST (issue #161): we pull each full collection (the API won't filter for us) but
        only KEEP rows that belong to a won quote in -WonQuoteId — so only won detail lands in
        bronze and flows to gold. modifiedAfter is UNVERIFIED on the line/section endpoints
        (spike #427), so this defaults to a full pull and leans on the bronze content-hash skip
        for idempotency (no re-bill on unchanged rows); -ModifiedAfter is exposed for when it is
        confirmed. Won-quote volume is small, so the full read is far inside the 60/min · 20k/day
        budget.

        VERIFIED SHAPE (spike #427, front-end migration 0083): lines live on separate endpoints,
        carry the linkage FKs below, and a value = Σ selected / non-optional lines split MRR vs
        one-off by is_recurring (computed in the silver merge, pipeline #95 — not here).
        Each flat column leads with the verified name and keeps a short fallback chain; an
        unmatched column lands NULL and nothing is lost (full payload in raw_payload).
    .PARAMETER WonQuoteId
        The won quote ids from the header pass (status 3). Detail is kept ONLY for these quotes.
        Empty/omitted → nothing is collected (returns four empty sets) without an API call.
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant (KQM is the MSP's own
        quoting system, not per-customer credentialed).
    .PARAMETER BaseUri
        KQM REST base. Default 'https://api.kaseyaquotemanager.com/v1' (verified).
    .PARAMETER ModifiedAfter
        Optional ISO-8601 lower bound — only applied once modifiedAfter is confirmed on these
        endpoints (#427). The task omits it (full pull + content-hash skip) for now.
    .PARAMETER ApiKey
        KQM API key override. Defaults to the SecretStore/Key Vault resolution.
    .OUTPUTS
        [pscustomobject] with Sections / Lines / SalesOrders / SalesOrderLines flat-row arrays.
    .EXAMPLE
        $won = Get-ImperionKqmOpportunity | Where-Object status -eq '3'
        Get-ImperionKqmOpportunityDetail -WonQuoteId $won.external_id | Set-ImperionKqmOpportunityDetailToBronze
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string[]] $WonQuoteId,
        [string] $TenantId,
        [string] $BaseUri = 'https://api.kaseyaquotemanager.com/v1',
        [string] $ModifiedAfter,
        [string] $ApiKey
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.LocalTenantId }

    $wonQuotes = @($WonQuoteId | Where-Object { $null -ne $_ -and "$_" -ne '' } | ForEach-Object { "$_" })
    $empty = [pscustomobject]@{ Sections = @(); Lines = @(); SalesOrders = @(); SalesOrderLines = @() }
    if ($wonQuotes.Count -eq 0) { return $empty } # no won quotes this pass → no detail, no API call

    $ApiKey = Resolve-ImperionKqmApiKey -ApiKey $ApiKey
    $wonQuoteSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$wonQuotes)

    # First non-null of a chain of plausible source names (StrictMode-safe via Get-ImperionMember).
    $firstOf = {
        param($record, [string[]] $candidates)
        foreach ($candidate in $candidates) {
            $value = Get-ImperionMember $record $candidate
            if ($null -ne $value -and "$value" -ne '') { return $value }
        }
    }

    # Pull a full detail collection (optionally incremental once #427 confirms modifiedAfter on
    # these endpoints). The base + querystring are resolved at the function body so the URI is
    # built from $BaseUri/$ModifiedAfter once; $pull just walks the pages for a given path.
    $base = $BaseUri.TrimEnd('/')
    $modifiedSuffix = if ($ModifiedAfter) { '?modifiedAfter=' + [uri]::EscapeDataString($ModifiedAfter) } else { '' }
    $pull = {
        param([string] $path)
        @(Invoke-ImperionKqmRequest -ApiKey $ApiKey -Uri ('{0}/{1}{2}' -f $base, $path, $modifiedSuffix))
    }

    # ── Sections (FK quoteID) → keep won quotes; collect their section ids for the line filter ──
    $sectionMap = [ordered]@{
        quote_id       = { param($s) & $firstOf $s @('quoteID', 'quoteId') }
        type           = { param($s) & $firstOf $s @('type') }
        line_number    = { param($s) & $firstOf $s @('lineNumber', 'lineNo') }
        is_multi_choice = { param($s) & $firstOf $s @('isMultiChoice', 'multiChoice') }
        is_selected    = { param($s) & $firstOf $s @('isSelected', 'selected') }
        title          = { param($s) & $firstOf $s @('title', 'name') }
    }
    $wonSections = @(& $pull 'quotesection' | Where-Object {
            $wonQuoteSet.Contains("$(& $firstOf $_ @('quoteID', 'quoteId'))")
        })
    $sectionRows = @($wonSections | ConvertTo-ImperionFlatObject -PropertyMap $sectionMap -Source 'kqm' -TenantId $TenantId -ExternalIdProperty 'id')
    $wonSectionSet = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@($wonSections | ForEach-Object { "$(& $firstOf $_ @('id'))" })
    )

    # ── Lines (FK quoteSectionID) → keep lines of won sections ────────────────────────────────
    $lineMap = [ordered]@{
        quote_section_id  = { param($l) & $firstOf $l @('quoteSectionID', 'quoteSectionId', 'sectionID') }
        line_number       = { param($l) & $firstOf $l @('lineNumber', 'lineNo') }
        product_id        = { param($l) & $firstOf $l @('productID', 'productId') }
        product_number    = { param($l) & $firstOf $l @('productNumber', 'sku') }
        title             = { param($l) & $firstOf $l @('title', 'name') }
        description       = { param($l) & $firstOf $l @('description') }
        price             = { param($l) & $firstOf $l @('price', 'unitPrice') }
        quantity          = { param($l) & $firstOf $l @('quantity', 'qty') }
        tax               = { param($l) & $firstOf $l @('tax') }
        tax_rate          = { param($l) & $firstOf $l @('taxRate') }
        discount_method   = { param($l) & $firstOf $l @('discountMethod') }
        discount_value    = { param($l) & $firstOf $l @('discountValue', 'discount') }
        is_optional       = { param($l) & $firstOf $l @('isOptional', 'optional') }
        is_selected       = { param($l) & $firstOf $l @('isSelected', 'selected') }
        is_recurring      = { param($l) & $firstOf $l @('isRecurring', 'recurring') }
        recurring_type    = { param($l) & $firstOf $l @('recurringType') }
        recurring_duration = { param($l) & $firstOf $l @('recurringDuration') }
        created_date      = { param($l) & $firstOf $l @('createdDate', 'dateCreated', 'created') }
        modified_date     = { param($l) & $firstOf $l @('modifiedDate', 'dateModified', 'modified') }
    }
    $lineRows = @(& $pull 'quoteline' |
            Where-Object { $wonSectionSet.Contains("$(& $firstOf $_ @('quoteSectionID', 'quoteSectionId', 'sectionID'))") } |
            ConvertTo-ImperionFlatObject -PropertyMap $lineMap -Source 'kqm' -TenantId $TenantId -ExternalIdProperty 'id')

    # ── Sales orders (FK quoteID) → keep won quotes; collect order ids for the order-line filter ─
    $orderMap = [ordered]@{
        quote_id          = { param($o) & $firstOf $o @('quoteID', 'quoteId') }
        order_number      = { param($o) & $firstOf $o @('orderNumber', 'number') }
        order_date        = { param($o) & $firstOf $o @('orderDate', 'date') }
        status            = { param($o) & $firstOf $o @('status', 'state') }
        fulfillment_status = { param($o) & $firstOf $o @('fulfillmentStatus') }
        entry_type        = { param($o) & $firstOf $o @('entryType') }
        customer_id       = { param($o) & $firstOf $o @('customerID', 'customerId') }
        created_date      = { param($o) & $firstOf $o @('createdDate', 'dateCreated', 'created') }
        modified_date     = { param($o) & $firstOf $o @('modifiedDate', 'dateModified', 'modified') }
    }
    $wonOrders = @(& $pull 'salesorder' | Where-Object {
            $wonQuoteSet.Contains("$(& $firstOf $_ @('quoteID', 'quoteId'))")
        })
    $orderRows = @($wonOrders | ConvertTo-ImperionFlatObject -PropertyMap $orderMap -Source 'kqm' -TenantId $TenantId -ExternalIdProperty 'id')
    $wonOrderSet = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@($wonOrders | ForEach-Object { "$(& $firstOf $_ @('id'))" })
    )

    # ── Sales-order lines (FK salesOrderID) → keep lines of won orders ────────────────────────
    $orderLineMap = [ordered]@{
        sales_order_id    = { param($l) & $firstOf $l @('salesOrderID', 'salesOrderId') }
        product_id        = { param($l) & $firstOf $l @('productID', 'productId') }
        line_number       = { param($l) & $firstOf $l @('lineNumber', 'lineNo') }
        cost              = { param($l) & $firstOf $l @('cost') }
        price             = { param($l) & $firstOf $l @('price', 'unitPrice') }
        tax               = { param($l) & $firstOf $l @('tax') }
        tax_rate          = { param($l) & $firstOf $l @('taxRate') }
        quantity          = { param($l) & $firstOf $l @('quantity', 'qty') }
        title             = { param($l) & $firstOf $l @('title', 'name') }
        description       = { param($l) & $firstOf $l @('description') }
        serial_numbers    = { param($l) & $firstOf $l @('serialNumbers', 'serials') }
        is_recurring      = { param($l) & $firstOf $l @('isRecurring', 'recurring') }
        recurring_type    = { param($l) & $firstOf $l @('recurringType') }
        recurring_duration = { param($l) & $firstOf $l @('recurringDuration') }
        created_date      = { param($l) & $firstOf $l @('createdDate', 'dateCreated', 'created') }
        modified_date     = { param($l) & $firstOf $l @('modifiedDate', 'dateModified', 'modified') }
    }
    $orderLineRows = @(& $pull 'salesorderline' |
            Where-Object { $wonOrderSet.Contains("$(& $firstOf $_ @('salesOrderID', 'salesOrderId'))") } |
            ConvertTo-ImperionFlatObject -PropertyMap $orderLineMap -Source 'kqm' -TenantId $TenantId -ExternalIdProperty 'id')

    [pscustomobject]@{
        Sections        = $sectionRows
        Lines           = $lineRows
        SalesOrders     = $orderRows
        SalesOrderLines = $orderLineRows
    }
}
