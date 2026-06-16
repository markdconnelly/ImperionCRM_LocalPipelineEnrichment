function Get-ImperionQboAccount {
    <#
    .SYNOPSIS
        Collect the full QuickBooks Online chart of accounts and flatten it to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for the QBO **Account** entity — the FULL chart of
        accounts (revenue / expense / asset / liability / equity), not just the expense slice. Part
        of the read-only full QBO finance pull into the intelligence / BI engine (ADR-0020, issue
        #197): the classification + rollup backbone for revenue / margin / account-health-from-spend
        BI. Pure reference data (account names like "Sales" / "Travel" — not comp, not client PII):
        flattens STRAIGHT to Postgres and SKIPS the IT Glue hub (ADR-0006). Reads the QBO OAuth
        access token + realm id from the SecretStore and pages the query endpoint via the shared
        connect layer (`Invoke-ImperionQboRequest`). Returns rows; does not write. Requires
        Initialize-ImperionContext.

        TARGET: bronze `qbo_accounts` (front-end-owned schema, ADR-0042 — front-end migration 0120,
        front-end #688). Idempotent external_id = the QBO Account `Id`. Deploy-ahead/gated on the
        QBO app registration.

        SCOPE vs the existing expense-only slice. `Get-ImperionQboExpenseAccount` →
        `qbo_expense_account` pulls ONLY `Classification = 'Expense'` accounts (the expense-category
        SoR, ADR-0014 #168). This collector pulls the WHOLE chart of accounts with NO classification
        filter. Whether `qbo_expense_account` becomes a VIEW over `qbo_accounts` or stays a separate
        table is a front-end migration-author call (ADR-0020 open item) — NOT decided here; this
        collector simply lands the full COA.

        CONFIRM BEFORE LIVE USE (gated on Mark's QBO app registration): the Account field names
        below, the query/paging shape, and the production host are modeled from the documented
        Intuit Accounting API but UNVERIFIED against the real company. Unmatched columns land NULL;
        the full payload survives in raw_payload.
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant.
    .PARAMETER BaseUri
        QBO API origin. Default production 'https://quickbooks.api.intuit.com'.
    .PARAMETER ModifiedAfter
        Optional ISO-8601 lower bound for incremental pulls (filters MetaData.LastUpdatedTime).
        Omit for a full backfill (the typical COA cadence — it is small).
    .EXAMPLE
        Get-ImperionQboAccount
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

    # FULL chart of accounts — no Classification filter (that is the expense-only slice's job).
    $query = 'SELECT * FROM Account'
    if ($ModifiedAfter) { $query += " WHERE MetaData.LastUpdatedTime > '$ModifiedAfter'" }

    $accounts = Invoke-ImperionQboRequest -AccessToken $accessToken -BaseUri $BaseUri `
        -RealmId $realmId -Query $query -EntityProperty 'Account'

    $firstOf = {
        param($record, [string[]] $candidates)
        foreach ($candidate in $candidates) {
            $value = Get-ImperionPropertyPath -InputObject $record -Path $candidate
            if ($null -ne $value -and "$value" -ne '') { return $value }
        }
    }

    # Documented Account fields lead each chain. Column set mirrors front-end migration 0120
    # (qbo_accounts); current_balance enables account-health-from-spend rollups.
    $map = [ordered]@{
        name                 = { param($a) & $firstOf $a @('Name', 'name') }
        fully_qualified_name = { param($a) & $firstOf $a @('FullyQualifiedName', 'fullyQualifiedName') }
        account_type         = { param($a) & $firstOf $a @('AccountType', 'accountType') }
        account_sub_type     = { param($a) & $firstOf $a @('AccountSubType', 'accountSubType') }
        classification       = { param($a) & $firstOf $a @('Classification', 'classification') }
        current_balance      = { param($a) & $firstOf $a @('CurrentBalance', 'currentBalance') }
        active               = { param($a) & $firstOf $a @('Active', 'active') }
        currency             = { param($a) & $firstOf $a @('CurrencyRef.value', 'currencyRef.value') }
        created_time         = { param($a) & $firstOf $a @('MetaData.CreateTime', 'metaData.createTime') }
        last_updated_time    = { param($a) & $firstOf $a @('MetaData.LastUpdatedTime', 'metaData.lastUpdatedTime') }
    }

    $accounts | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'qbo' -TenantId $TenantId -ExternalIdProperty 'Id'
}
