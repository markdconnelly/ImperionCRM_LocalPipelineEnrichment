function Get-ImperionQboInvoice {
    <#
    .SYNOPSIS
        Collect QuickBooks Online invoices and flatten them to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for the QBO **Invoice** entity — what the MSP has
        billed customers. Part of the read-only full QBO finance pull into the intelligence / BI
        engine (ADR-0020, issue #197): revenue billed, and A/R when unpaid. Pure finance data:
        flattens STRAIGHT to Postgres and SKIPS the IT Glue hub (ADR-0006). Reads the QBO OAuth
        access token + realm (company) id from the SecretStore (`qbo-access-token` /
        `qbo-realm-id`) and pages the query endpoint via the shared connect layer
        (`Invoke-ImperionQboRequest`, the same one connection the payment-fact + chart-of-accounts
        pulls use — one connection, many readers, no second app reg). Returns rows; does not write.
        Requires Initialize-ImperionContext.

        TARGET: bronze `qbo_invoices` (front-end-owned schema, ADR-0042 — front-end migration 0120,
        front-end #688). Idempotent external_id = the QBO Invoice `Id` (stable, realm-scoped). The
        collector is deploy-ahead/gated on the QBO app registration (the scheduled task logs + exits
        until both `qbo-access-token`/`qbo-realm-id` are provisioned).

        CONFIRM BEFORE LIVE USE (gated on Mark's QBO app registration — the standing QBO blocker,
        same as backend #104): the Invoice field names below, the query/paging shape, and the
        production host are modeled from the documented Intuit Accounting API but UNVERIFIED against
        the real company. Each flat column leads with the documented name and keeps a short fallback
        chain; an unmatched column lands NULL and nothing is lost (full payload in raw_payload).
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant (QBO is the MSP's own
        books, not per-customer credentialed).
    .PARAMETER BaseUri
        QBO API origin. Default production 'https://quickbooks.api.intuit.com'.
    .PARAMETER ModifiedAfter
        Optional ISO-8601 lower bound for incremental pulls (filters MetaData.LastUpdatedTime).
        Omit for a full backfill.
    .EXAMPLE
        Get-ImperionQboInvoice -ModifiedAfter (Get-Date).AddDays(-7).ToUniversalTime().ToString('o')
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
    if (-not $TenantId) { $TenantId = $cfg.LocalTenantId }

    $accessToken = Get-ImperionSecretValue -Name $names.QboAccessToken
    $realmId = Get-ImperionSecretValue -Name $names.QboRealmId

    $query = 'SELECT * FROM Invoice'
    if ($ModifiedAfter) { $query += " WHERE MetaData.LastUpdatedTime > '$ModifiedAfter'" }

    $invoices = Invoke-ImperionQboRequest -AccessToken $accessToken -BaseUri $BaseUri `
        -RealmId $realmId -Query $query -EntityProperty 'Invoice'

    $firstOf = {
        param($record, [string[]] $candidates)
        foreach ($candidate in $candidates) {
            $value = Get-ImperionPropertyPath -InputObject $record -Path $candidate
            if ($null -ne $value -and "$value" -ne '') { return $value }
        }
    }

    # Documented Invoice fields lead each chain; fallbacks tolerate casing/shape drift. Column set
    # mirrors front-end migration 0120 (qbo_invoices). total_amount/balance carry the A/R signal.
    $map = [ordered]@{
        doc_number        = { param($i) & $firstOf $i @('DocNumber', 'docNumber') }
        txn_date          = { param($i) & $firstOf $i @('TxnDate', 'txnDate') }
        due_date          = { param($i) & $firstOf $i @('DueDate', 'dueDate') }
        total_amount      = { param($i) & $firstOf $i @('TotalAmt', 'totalAmt') }            # revenue billed
        balance           = { param($i) & $firstOf $i @('Balance', 'balance') }              # A/R outstanding
        customer_ref      = { param($i) & $firstOf $i @('CustomerRef.value', 'customerRef.value') }
        customer_name     = { param($i) & $firstOf $i @('CustomerRef.name', 'customerRef.name') }
        currency          = { param($i) & $firstOf $i @('CurrencyRef.value', 'currencyRef.value') }
        created_time      = { param($i) & $firstOf $i @('MetaData.CreateTime', 'metaData.createTime') }
        last_updated_time = { param($i) & $firstOf $i @('MetaData.LastUpdatedTime', 'metaData.lastUpdatedTime') }
    }

    $invoices | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'qbo' -TenantId $TenantId -ExternalIdProperty 'Id'
}
