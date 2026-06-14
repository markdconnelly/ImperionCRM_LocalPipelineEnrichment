function Get-ImperionQboBillPayment {
    <#
    .SYNOPSIS
        Collect QuickBooks Online vendor bill-payments and flatten them to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for the QBO **BillPayment** entity — the MSP's own
        accounts-payable payments to vendors (in v1, the 1099 contractors). Pure finance data:
        flattens STRAIGHT to Postgres and SKIPS the IT Glue hub (ADR-0006). Reads the QBO OAuth
        access token + realm (company) id from the SecretStore (`qbo-access-token` /
        `qbo-realm-id`) and pages the query endpoint via the connect layer. Returns rows; does
        not write. Requires Initialize-ImperionContext.

        WHY THIS REPO HOLDS IT — the authoritative PAYMENT FACT. The front-end time-tracking
        flow (ADR-0082) marks a timesheet **Paid** only when the backend Payroll Reconciliation
        (ImperionCRM_Backend#105) matches expected pay to a real QBO payment. QBO is **read-only
        and authoritative for the payment fact alone — the app never pays.** This collector lands
        the bronze fact; the backend reads it. The payment AMOUNT is the fact we need and is
        landed here; it is NOT comp data (pay_rate stays in the front-end finance-gated 0085
        store) and is never logged (metric counts only, CLAUDE.md §8).

        TARGET: bronze `qbo_bill_payments` (front-end-owned schema, ADR-0042 — a migration is
        PROPOSED in docs/integrations/quickbooks-online.md + this repo's QBO ADR; the table does
        not exist yet, so the scheduled task is GATED/deploy-ahead like UniFi/Plaud). Idempotent
        external_id = the QBO BillPayment `Id` (stable, realm-scoped).

        CONFIRM BEFORE LIVE USE (gated on Mark's QBO app registration — the standing
        time-tracking blocker, same as backend #104): the BillPayment field names below, the
        query/paging shape, and the production host are modeled from the documented Intuit
        Accounting API but UNVERIFIED against the real company. Each flat column leads with the
        documented name and keeps a short fallback chain; an unmatched column lands NULL and
        nothing is lost (full payload in raw_payload) — the KQM/DocuSign precedent.
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant (QBO is the MSP's own
        books, not per-customer credentialed — like KQM).
    .PARAMETER BaseUri
        QBO API origin. Default production 'https://quickbooks.api.intuit.com'.
    .PARAMETER ModifiedAfter
        Optional ISO-8601 lower bound for incremental pulls (filters MetaData.LastUpdatedTime).
        Omit for a full backfill.
    .EXAMPLE
        Get-ImperionQboBillPayment -ModifiedAfter (Get-Date).AddDays(-7).ToUniversalTime().ToString('o')
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

    # QBO's SQL-like query: incremental on MetaData.LastUpdatedTime when a bound is given.
    # The clause is single-quoted in the QBO query grammar; the timestamp is operator-supplied
    # (ISO-8601), never user input.
    $query = 'SELECT * FROM BillPayment'
    if ($ModifiedAfter) { $query += " WHERE MetaData.LastUpdatedTime > '$ModifiedAfter'" }

    $payments = Invoke-ImperionQboRequest -AccessToken $accessToken -BaseUri $BaseUri `
        -RealmId $realmId -Query $query -EntityProperty 'BillPayment'

    # First non-null of a chain of plausible source names (StrictMode-safe via Get-ImperionMember).
    $firstOf = {
        param($record, [string[]] $candidates)
        foreach ($candidate in $candidates) {
            $value = Get-ImperionPropertyPath -InputObject $record -Path $candidate
            if ($null -ne $value -and "$value" -ne '') { return $value }
        }
    }

    # Documented BillPayment fields lead each chain; fallbacks tolerate casing/shape drift.
    $map = [ordered]@{
        txn_date          = { param($p) & $firstOf $p @('TxnDate', 'txnDate') }
        total_amount      = { param($p) & $firstOf $p @('TotalAmt', 'totalAmt') }       # the payment FACT (not comp)
        vendor_id         = { param($p) & $firstOf $p @('VendorRef.value', 'vendorRef.value') }
        vendor_name       = { param($p) & $firstOf $p @('VendorRef.name', 'vendorRef.name') }
        pay_type          = { param($p) & $firstOf $p @('PayType', 'payType') }          # Check / CreditCard
        doc_number        = { param($p) & $firstOf $p @('DocNumber', 'docNumber') }       # payment reference
        currency          = { param($p) & $firstOf $p @('CurrencyRef.value', 'currencyRef.value') }
        created_time      = { param($p) & $firstOf $p @('MetaData.CreateTime', 'metaData.createTime') }
        last_updated_time = { param($p) & $firstOf $p @('MetaData.LastUpdatedTime', 'metaData.lastUpdatedTime') }
    }

    $payments | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'qbo' -TenantId $TenantId -ExternalIdProperty 'Id'
}
