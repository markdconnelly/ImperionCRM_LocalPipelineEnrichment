function Get-ImperionQboEstimate {
    <#
    .SYNOPSIS
        Collect QuickBooks Online estimates and flatten them to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for the QBO **Estimate** entity — quotes / committed-
        but-unbilled work. Part of the read-only full QBO finance pull into the intelligence / BI
        engine (ADR-0020, issue #197): the finance-side pipeline signal (an Estimate accepted but
        not yet invoiced is committed-but-unbilled revenue). Pure finance data: flattens STRAIGHT to
        Postgres and SKIPS the IT Glue hub (ADR-0006). Reads the QBO OAuth access token + realm id
        from the SecretStore and pages the query endpoint via the shared connect layer
        (`Invoke-ImperionQboRequest`). Returns rows; does not write. Requires
        Initialize-ImperionContext.

        TARGET: bronze `qbo_estimates` (front-end-owned schema, ADR-0042 — front-end migration 0120,
        front-end #688). Idempotent external_id = the QBO Estimate `Id`. Deploy-ahead/gated on the
        QBO app registration.

        CONFIRM BEFORE LIVE USE (gated on Mark's QBO app registration): the Estimate field names
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
        Get-ImperionQboEstimate
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

    $query = 'SELECT * FROM Estimate'
    if ($ModifiedAfter) { $query += " WHERE MetaData.LastUpdatedTime > '$ModifiedAfter'" }

    $estimates = Invoke-ImperionQboRequest -AccessToken $accessToken -BaseUri $BaseUri `
        -RealmId $realmId -Query $query -EntityProperty 'Estimate'

    $firstOf = {
        param($record, [string[]] $candidates)
        foreach ($candidate in $candidates) {
            $value = Get-ImperionPropertyPath -InputObject $record -Path $candidate
            if ($null -ne $value -and "$value" -ne '') { return $value }
        }
    }

    # Documented Estimate fields lead each chain. Column set mirrors front-end migration 0120
    # (qbo_estimates). txn_status (Accepted/Pending/Closed/Rejected) is the pipeline signal.
    $map = [ordered]@{
        doc_number        = { param($e) & $firstOf $e @('DocNumber', 'docNumber') }
        txn_date          = { param($e) & $firstOf $e @('TxnDate', 'txnDate') }
        expiration_date   = { param($e) & $firstOf $e @('ExpirationDate', 'expirationDate') }
        txn_status        = { param($e) & $firstOf $e @('TxnStatus', 'txnStatus') }            # Accepted / Pending / Closed
        total_amount      = { param($e) & $firstOf $e @('TotalAmt', 'totalAmt') }
        customer_ref      = { param($e) & $firstOf $e @('CustomerRef.value', 'customerRef.value') }
        customer_name     = { param($e) & $firstOf $e @('CustomerRef.name', 'customerRef.name') }
        currency          = { param($e) & $firstOf $e @('CurrencyRef.value', 'currencyRef.value') }
        created_time      = { param($e) & $firstOf $e @('MetaData.CreateTime', 'metaData.createTime') }
        last_updated_time = { param($e) & $firstOf $e @('MetaData.LastUpdatedTime', 'metaData.lastUpdatedTime') }
    }

    $estimates | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'qbo' -TenantId $TenantId -ExternalIdProperty 'Id'
}
