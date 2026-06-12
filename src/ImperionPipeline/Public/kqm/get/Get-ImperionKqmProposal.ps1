function Get-ImperionKqmProposal {
    <#
    .SYNOPSIS
        Collect KQM quotes (proposals) and flatten them to kqm_proposals bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for Kaseya Quote Manager, issue #98. Pure
        CRM/sales data: flattens straight to Postgres and SKIPS the IT Glue hub
        (ADR-0006). Pages /v1/quote via the connect layer (apikey querystring — the URL
        is secret-bearing and is never logged) with an optional modifiedAfter incremental
        filter. Target: bronze `kqm_proposals` (front-end migration 0038) → silver
        `proposal` via the cloud Pipeline merge. Returns rows; does not write. Requires
        Initialize-ImperionContext.

        Key resolution: explicit -ApiKey; else SecretStore `kqm-api-key` (mirror); else
        Key Vault `KQM-API-Key` (the operator-provisioned original) via the cert SP.

        VERIFY-LIVE-FIRST (the issue's gate): the quote FIELD NAMES below are documented-
        shape ASSUMPTIONS — KQM's public docs don't enumerate response fields. Each flat
        column tries a small chain of plausible names and lands NULL when none match;
        nothing is lost (full payload in raw_payload). Before trusting the flat columns,
        run `Get-ImperionKqmFieldName` (dumps live field NAMES, never values) and correct
        the map in ONE place here.
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant (KQM is the
        MSP's own quoting system, not per-customer credentialed).
    .PARAMETER BaseUri
        KQM REST base. Default 'https://api.kaseyaquotemanager.com/v1' (verified).
    .PARAMETER ModifiedAfter
        Optional ISO-8601 lower bound for incremental pulls (the documented
        modifiedAfter filter). Omit for a full backfill.
    .PARAMETER ApiKey
        KQM API key override. Defaults to the SecretStore/Key Vault resolution above.
    .EXAMPLE
        Get-ImperionKqmProposal -ModifiedAfter (Get-Date).AddDays(-7).ToUniversalTime().ToString('o')
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

    # ASSUMED field names (see DESCRIPTION) — verify with Get-ImperionKqmFieldName, fix here.
    $map = [ordered]@{
        name        = { param($quote) & $firstOf $quote @('name', 'title', 'reference', 'quoteNumber') }
        status      = { param($quote) & $firstOf $quote @('status', 'state') }
        total       = { param($quote) & $firstOf $quote @('total', 'totalAmount', 'grandTotal', 'totalIncTax') }
        account_ref = { param($quote) & $firstOf $quote @('customerName', 'companyName', 'customerId', 'customer') }
        created_at  = { param($quote) & $firstOf $quote @('createdDate', 'dateCreated', 'created') }
        updated_at  = { param($quote) & $firstOf $quote @('modifiedDate', 'dateModified', 'modified', 'lastModified') }
    }

    $quotes | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'kqm' -TenantId $TenantId -ExternalIdProperty 'id'
}
