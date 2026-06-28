function Get-ImperionQboPayment {
    <#
    .SYNOPSIS
        Collect QuickBooks Online customer payments and flatten them to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for the QBO **Payment** entity — cash received against
        customer invoices. Part of the read-only full QBO finance pull into the intelligence / BI
        engine (ADR-0020, issue #197): the cash-in side of the A/R picture (an Invoice billed; a
        Payment settles it). Pure finance data: flattens STRAIGHT to Postgres and SKIPS the IT Glue
        hub (ADR-0006). Reads the QBO OAuth access token + realm id from the SecretStore
        (`qbo-access-token` / `qbo-realm-id`) and pages the query endpoint via the shared connect
        layer (`Invoke-ImperionQboRequest`). Returns rows; does not write. Requires
        Initialize-ImperionContext.

        TARGET: bronze `qbo_payments` (front-end-owned schema, ADR-0042 — front-end migration 0120,
        front-end #688). Idempotent external_id = the QBO Payment `Id`. Deploy-ahead/gated on the
        QBO app registration (the scheduled task logs + exits until the secrets land).

        NOTE: this is the CUSTOMER payment (cash IN against an invoice) — distinct from the
        `Purchase` entity (cash OUT, the payroll/expense payment fact, ADR-0014 #174), which keeps
        its own collector + `qbo_purchases` table.

        CONFIRM BEFORE LIVE USE (gated on Mark's QBO app registration): the Payment field names
        below, the query/paging shape, and the production host are modeled from the documented
        Intuit Accounting API but UNVERIFIED against the real company. Unmatched columns land NULL;
        the full payload survives in raw_payload.
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant.
    .PARAMETER BaseUri
        QBO API origin. Default production 'https://quickbooks.api.intuit.com'.
    .PARAMETER ModifiedAfter
        Optional ISO-8601 lower bound for incremental pulls (filters MetaData.LastUpdatedTime).
        Omit for a full backfill.
    .EXAMPLE
        Get-ImperionQboPayment -ModifiedAfter (Get-Date).AddDays(-7).ToUniversalTime().ToString('o')
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

    $query = 'SELECT * FROM Payment'
    if ($ModifiedAfter) { $query += " WHERE MetaData.LastUpdatedTime > '$ModifiedAfter'" }

    $payments = Invoke-ImperionQboRequest -AccessToken $accessToken -BaseUri $BaseUri `
        -RealmId $realmId -Query $query -EntityProperty 'Payment'

    $firstOf = {
        param($record, [string[]] $candidates)
        foreach ($candidate in $candidates) {
            $value = Get-ImperionPropertyPath -InputObject $record -Path $candidate
            if ($null -ne $value -and "$value" -ne '') { return $value }
        }
    }

    # Documented Payment fields lead each chain. Column set mirrors front-end migration 0120
    # (qbo_payments). total_amount/unapplied carry the cash-received signal.
    $map = [ordered]@{
        txn_date          = { param($p) & $firstOf $p @('TxnDate', 'txnDate') }
        total_amount      = { param($p) & $firstOf $p @('TotalAmt', 'totalAmt') }              # cash received
        unapplied_amount  = { param($p) & $firstOf $p @('UnappliedAmt', 'unappliedAmt') }
        customer_ref      = { param($p) & $firstOf $p @('CustomerRef.value', 'customerRef.value') }
        customer_name     = { param($p) & $firstOf $p @('CustomerRef.name', 'customerRef.name') }
        deposit_account   = { param($p) & $firstOf $p @('DepositToAccountRef.value', 'depositToAccountRef.value') }
        payment_method    = { param($p) & $firstOf $p @('PaymentMethodRef.value', 'paymentMethodRef.value') }
        currency          = { param($p) & $firstOf $p @('CurrencyRef.value', 'currencyRef.value') }
        created_time      = { param($p) & $firstOf $p @('MetaData.CreateTime', 'metaData.createTime') }
        last_updated_time = { param($p) & $firstOf $p @('MetaData.LastUpdatedTime', 'metaData.lastUpdatedTime') }
    }

    $payments | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'qbo' -TenantId $TenantId -ExternalIdProperty 'Id'
}
