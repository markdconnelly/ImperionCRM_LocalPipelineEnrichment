function Get-ImperionKqmOpportunity {
    <#
    .SYNOPSIS
        Collect KQM quotes (opportunities) and flatten them to kqm_opportunities bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for Kaseya Quote Manager. Pure CRM/sales data:
        flattens straight to Postgres and SKIPS the IT Glue hub. Pages /v1/quote via the
        connect layer (apikey querystring — the URL is secret-bearing and is never logged)
        with an optional modifiedAfter incremental filter. Returns rows; does not write.
        Requires Initialize-ImperionContext.

        TARGET (front-end migration 0083, ADR-0080/0039 — supersedes the dropped, mis-modeled
        kqm_proposals of 0038): KQM is ONE bronze source of the silver `opportunity`, not a
        standalone proposal object. This collector pulls the quote HEADER → bronze
        `kqm_opportunities`. The won-quote DETAIL (sections/lines/sales orders) is a separate
        collector set (issue #161); the header alone carries the won-trigger and the
        sale→delivery seam and feeds the `opportunity_bronze_all` union view.

        VERIFIED LIVE SHAPE (spike #427, recorded on front-end issue #427):
        - `status` is an INT enum CODE (1 open/2 sent/3 WON/90 dead), not text — bronze keeps
          it as text; silver interprets 3 = won.
        - `salesOrderId` is present ⇔ status 3 (the won marker; drives the #161 detail pull).
        - The header has NO `name` and NO `total` (silver sums selected lines).
        - The Autotask FKs (`autotaskOpportunityID`/`autotaskOrganizationID`/`autotaskQuoteID`)
          are populated and ARE the sale→delivery seam — no mapping table needed.

        Each flat column still leads with the verified name and keeps a short fallback chain;
        an unmatched column lands NULL and nothing is lost (full payload in raw_payload).
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant (KQM is the
        MSP's own quoting system, not per-customer credentialed).
    .PARAMETER BaseUri
        KQM REST base. Default 'https://api.kaseyaquotemanager.com/v1' (verified).
    .PARAMETER ModifiedAfter
        Optional ISO-8601 lower bound for incremental pulls (the documented
        modifiedAfter filter). Omit for a full backfill.
    .PARAMETER ApiKey
        KQM API key override. Defaults to the SecretStore/Key Vault resolution.
    .EXAMPLE
        Get-ImperionKqmOpportunity -ModifiedAfter (Get-Date).AddDays(-7).ToUniversalTime().ToString('o')
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId,
        [string] $BaseUri = 'https://api.kaseyaquotemanager.com/v1',
        [string] $ModifiedAfter,
        [string] $ApiKey
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }
    $ApiKey = Resolve-ImperionKqmApiKey -ApiKey $ApiKey

    $uri = '{0}/quote' -f $BaseUri.TrimEnd('/')
    if ($ModifiedAfter) { $uri += '?modifiedAfter=' + [uri]::EscapeDataString($ModifiedAfter) }
    $quotes = Invoke-ImperionKqmRequest -ApiKey $ApiKey -Uri $uri

    # First non-null of a chain of plausible source names (StrictMode-safe via Get-ImperionMember).
    $firstOf = {
        param($record, [string[]] $candidates)
        foreach ($candidate in $candidates) {
            $value = Get-ImperionMember $record $candidate
            if ($null -ne $value -and "$value" -ne '') { return $value }
        }
    }

    # Verified header field names (spike #427) lead each chain; fallbacks tolerate casing drift.
    $map = [ordered]@{
        quote_number             = { param($q) & $firstOf $q @('quoteNumber', 'number', 'reference') }
        code                     = { param($q) & $firstOf $q @('code') }
        title                    = { param($q) & $firstOf $q @('title', 'name') }
        status                   = { param($q) & $firstOf $q @('status', 'state') }            # INT enum (3 = won)
        sales_order_id           = { param($q) & $firstOf $q @('salesOrderId', 'salesOrderID') }  # present ⇔ won
        customer_id              = { param($q) & $firstOf $q @('customerID', 'customerId') }
        autotask_opportunity_id  = { param($q) & $firstOf $q @('autotaskOpportunityID', 'autotaskOpportunityId') }
        autotask_organization_id = { param($q) & $firstOf $q @('autotaskOrganizationID', 'autotaskOrganizationId') }
        autotask_quote_id        = { param($q) & $firstOf $q @('autotaskQuoteID', 'autotaskQuoteId') }
        contact_name             = { param($q) & $firstOf $q @('contactName') }
        contact_email            = { param($q) & $firstOf $q @('contactEmail') }
        owner_employee_id        = { param($q) & $firstOf $q @('ownerEmployeeID', 'ownerEmployeeId') }
        created_date             = { param($q) & $firstOf $q @('createdDate', 'dateCreated', 'created') }
        modified_date            = { param($q) & $firstOf $q @('modifiedDate', 'dateModified', 'modified', 'lastModified') }
        expiry_date              = { param($q) & $firstOf $q @('expiryDate', 'expiresOn', 'validUntil') }
    }

    $quotes | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'kqm' -TenantId $TenantId -ExternalIdProperty 'id'
}
