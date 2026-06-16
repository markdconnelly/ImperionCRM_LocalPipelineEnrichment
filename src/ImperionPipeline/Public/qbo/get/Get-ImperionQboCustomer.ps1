function Get-ImperionQboCustomer {
    <#
    .SYNOPSIS
        Collect QuickBooks Online customers and flatten them to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for the QBO **Customer** entity — the finance-side
        customer master. Part of the read-only full QBO finance pull into the intelligence / BI
        engine (ADR-0020, issue #197): the join key from finance facts (invoices / payments) to the
        silver `account`, and the carrier of per-customer balance. Pure finance data: flattens
        STRAIGHT to Postgres and SKIPS the IT Glue hub (ADR-0006). Reads the QBO OAuth access token
        + realm id from the SecretStore and pages the query endpoint via the shared connect layer
        (`Invoke-ImperionQboRequest`). Returns rows; does not write. Requires
        Initialize-ImperionContext.

        TARGET: bronze `qbo_customers` (front-end-owned schema, ADR-0042 — front-end migration 0120,
        front-end #688). Idempotent external_id = the QBO Customer `Id`. Deploy-ahead/gated on the
        QBO app registration.

        PII NOTE (CLAUDE.md §8): Customer rows carry client financial PII (display/company names,
        balance). They land tagged with the owning tenant; the structured logs record COUNTS ONLY,
        never names or balances.

        CONFIRM BEFORE LIVE USE (gated on Mark's QBO app registration): the Customer field names
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
        Get-ImperionQboCustomer
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

    $query = 'SELECT * FROM Customer'
    if ($ModifiedAfter) { $query += " WHERE MetaData.LastUpdatedTime > '$ModifiedAfter'" }

    $customers = Invoke-ImperionQboRequest -AccessToken $accessToken -BaseUri $BaseUri `
        -RealmId $realmId -Query $query -EntityProperty 'Customer'

    $firstOf = {
        param($record, [string[]] $candidates)
        foreach ($candidate in $candidates) {
            $value = Get-ImperionPropertyPath -InputObject $record -Path $candidate
            if ($null -ne $value -and "$value" -ne '') { return $value }
        }
    }

    # Documented Customer fields lead each chain. Column set mirrors front-end migration 0120
    # (qbo_customers). display_name is the join hint to the silver account.
    $map = [ordered]@{
        display_name      = { param($c) & $firstOf $c @('DisplayName', 'displayName') }
        company_name      = { param($c) & $firstOf $c @('CompanyName', 'companyName') }
        active            = { param($c) & $firstOf $c @('Active', 'active') }
        balance           = { param($c) & $firstOf $c @('Balance', 'balance') }
        primary_email     = { param($c) & $firstOf $c @('PrimaryEmailAddr.Address', 'primaryEmailAddr.address') }
        primary_phone     = { param($c) & $firstOf $c @('PrimaryPhone.FreeFormNumber', 'primaryPhone.freeFormNumber') }
        currency          = { param($c) & $firstOf $c @('CurrencyRef.value', 'currencyRef.value') }
        created_time      = { param($c) & $firstOf $c @('MetaData.CreateTime', 'metaData.createTime') }
        last_updated_time = { param($c) & $firstOf $c @('MetaData.LastUpdatedTime', 'metaData.lastUpdatedTime') }
    }

    $customers | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'qbo' -TenantId $TenantId -ExternalIdProperty 'Id'
}
