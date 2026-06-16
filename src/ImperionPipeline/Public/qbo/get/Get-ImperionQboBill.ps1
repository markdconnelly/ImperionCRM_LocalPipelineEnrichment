function Get-ImperionQboBill {
    <#
    .SYNOPSIS
        Collect QuickBooks Online vendor bills (A/P) and flatten them to bronze rows; degrade
        gracefully when the subscription has no Accounts Payable.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for the QBO **Bill** entity — vendor bills, the
        Accounts-Payable / procurement signal (what the MSP owes). Part of the read-only full QBO
        finance pull into the intelligence / BI engine (ADR-0020, issue #197). Pure finance data:
        flattens STRAIGHT to Postgres and SKIPS the IT Glue hub (ADR-0006). Reads the QBO OAuth
        access token + realm id from the SecretStore and pages the query endpoint via the shared
        connect layer (`Invoke-ImperionQboRequest`). Returns rows; does not write. Requires
        Initialize-ImperionContext.

        TARGET: bronze `qbo_bills` (front-end-owned schema, ADR-0042 — front-end migration 0120,
        front-end #688). Idempotent external_id = the QBO Bill `Id`. Deploy-ahead/gated on the QBO
        app registration.

        SIMPLE START → GRACEFUL DEGRADE (CONFIRM-BEFORE-LIVE, ADR-0020 §1 open item). Imperion's
        QBO company is **Simple Start**, which has **no Accounts Payable**, so `Bill` may return
        "Feature Not Supported" from the Intuit Accounting API — the same constraint that re-targeted
        the payment fact `BillPayment` → `Purchase` (#174). When that happens this collector does
        NOT hard-fail: it logs a clear WARNING and returns NO rows (the A/P signal is then carried by
        `qbo_purchases` + `qbo_accounts` expense classifications, and `qbo_bills` stays dormant).
        `qbo_bills` is modeled for completeness and a future non-Simple-Start tier. Any OTHER error
        (token expiry, transport) is re-thrown so the schedule fails loudly per the standard posture.

        CONFIRM BEFORE LIVE USE (gated on Mark's QBO app registration): whether `Bill` is available
        on this Simple Start company AT ALL, plus the Bill field names below, the query/paging shape,
        and the production host — all modeled from the documented Intuit Accounting API but
        UNVERIFIED against the real company. Unmatched columns land NULL; the full payload survives
        in raw_payload.
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant.
    .PARAMETER BaseUri
        QBO API origin. Default production 'https://quickbooks.api.intuit.com'.
    .PARAMETER ModifiedAfter
        Optional ISO-8601 lower bound for incremental pulls (filters MetaData.LastUpdatedTime).
        Omit for a full backfill.
    .EXAMPLE
        Get-ImperionQboBill
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId,
        [string] $BaseUri = 'https://quickbooks.api.intuit.com',
        [string] $ModifiedAfter
    )

    $cfg = Get-ImperionConfig
    $names = Get-ImperionSecretNames
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }

    $accessToken = Get-ImperionSecretValue -Name $names.QboAccessToken
    $realmId = Get-ImperionSecretValue -Name $names.QboRealmId

    $query = 'SELECT * FROM Bill'
    if ($ModifiedAfter) { $query += " WHERE MetaData.LastUpdatedTime > '$ModifiedAfter'" }

    try {
        $bills = Invoke-ImperionQboRequest -AccessToken $accessToken -BaseUri $BaseUri `
            -RealmId $realmId -Query $query -EntityProperty 'Bill'
    }
    catch {
        # Simple Start has no Accounts Payable, so `Bill` raises a QBO "Feature Not Supported"
        # fault (HTTP 4xx, surfaced in the thrown message by Invoke-ImperionRestWithRetry). That is
        # an EXPECTED tier limit, not a failure: log a clear warning and yield no rows so the A/P
        # leg simply stays dormant. Any other error (token expiry, transport) re-throws to fail
        # loudly per the standard posture.
        if ($_.Exception.Message -match '(?i)Feature[\s-]?Not[\s-]?Supported|AuthorizationFailed.*Bill|6000') {
            Write-ImperionLog -Level Warn -Source 'qbo' -Message ('qbo_bills skipped: Accounts Payable / Bill is not available on this QBO subscription (Simple Start has no A/P). The A/P signal is carried by qbo_purchases + qbo_accounts.')
            return
        }
        throw
    }

    $firstOf = {
        param($record, [string[]] $candidates)
        foreach ($candidate in $candidates) {
            $value = Get-ImperionPropertyPath -InputObject $record -Path $candidate
            if ($null -ne $value -and "$value" -ne '') { return $value }
        }
    }

    # Documented Bill fields lead each chain. Column set mirrors front-end migration 0120
    # (qbo_bills). total_amount/balance carry the A/P-owed signal; vendor_ref is the payee.
    $map = [ordered]@{
        doc_number        = { param($b) & $firstOf $b @('DocNumber', 'docNumber') }
        txn_date          = { param($b) & $firstOf $b @('TxnDate', 'txnDate') }
        due_date          = { param($b) & $firstOf $b @('DueDate', 'dueDate') }
        total_amount      = { param($b) & $firstOf $b @('TotalAmt', 'totalAmt') }            # A/P owed
        balance           = { param($b) & $firstOf $b @('Balance', 'balance') }              # A/P outstanding
        vendor_ref        = { param($b) & $firstOf $b @('VendorRef.value', 'vendorRef.value') }
        vendor_name       = { param($b) & $firstOf $b @('VendorRef.name', 'vendorRef.name') }
        ap_account_ref    = { param($b) & $firstOf $b @('APAccountRef.value', 'aPAccountRef.value') }
        currency          = { param($b) & $firstOf $b @('CurrencyRef.value', 'currencyRef.value') }
        created_time      = { param($b) & $firstOf $b @('MetaData.CreateTime', 'metaData.createTime') }
        last_updated_time = { param($b) & $firstOf $b @('MetaData.LastUpdatedTime', 'metaData.lastUpdatedTime') }
    }

    $bills | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'qbo' -TenantId $TenantId -ExternalIdProperty 'Id'
}
