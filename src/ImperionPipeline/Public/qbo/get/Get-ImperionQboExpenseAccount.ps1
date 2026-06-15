function Get-ImperionQboExpenseAccount {
    <#
    .SYNOPSIS
        Collect QuickBooks Online expense-type chart-of-accounts and flatten them to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for the QBO **Account** entity, scoped to the
        expense-type accounts — the MSP's expense **category system of record** (front-end
        ADR-0083, epic markdconnelly/ImperionCRM#482). Pure finance/reference data: flattens
        STRAIGHT to Postgres and SKIPS the IT Glue hub (ADR-0006). Reads the QBO OAuth access
        token + realm (company) id from the SecretStore (`qbo-access-token` / `qbo-realm-id`) and
        pages the query endpoint via the connect layer (`Invoke-ImperionQboRequest`, shared with
        the bill-payment pull). Returns rows; does not write. Requires Initialize-ImperionContext.

        WHY THIS REPO HOLDS IT — QuickBooks is the CATEGORY system of record. The chart of
        accounts is synced **read-only** to bronze `qbo_expense_account`; a front-end admin then
        maps each account to a clean website `expense_category` (front-end #489). The app
        **never writes QuickBooks** — when finance needs a missing category they create it in
        QuickBooks manually, and the next pull surfaces it for mapping. This is reference data,
        not comp data and not PII (account names like "Travel" / "Office Supplies").

        TARGET: bronze `qbo_expense_account` (front-end-owned schema, ADR-0042 — a migration is
        PROPOSED in docs/integrations/quickbooks-online.md + ADR-0014; the table does not exist
        yet, so the scheduled task is GATED/deploy-ahead like the bill-payment pull). Idempotent
        external_id = the QBO Account `Id` (stable, realm-scoped).

        EXPENSE-TYPE FILTER. Only accounts whose `Classification = 'Expense'` are requested
        (the QBO classification that covers `AccountType` Expense / CostOfGoodsSold / OtherExpense).
        The boundary (issue #168): this is the chart-of-accounts bulk sync ONLY — the backend QBO
        read client owns the bill-payment read for reconciliation (a separate pull, ADR-0014).

        CONFIRM BEFORE LIVE USE (gated on Mark's QBO app registration + the chart-of-accounts read
        scope, front-end markdconnelly/ImperionCRM#497): the Account field names below, the
        Classification filter value, the query/paging shape, and the production host are modeled
        from the documented Intuit Accounting API but UNVERIFIED against the real company. Each flat
        column leads with the documented name and keeps a short fallback chain; an unmatched column
        lands NULL and nothing is lost (full payload in raw_payload) — the bill-payment precedent.
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant (QBO is the MSP's own
        books, not per-customer credentialed — like the bill-payment pull).
    .PARAMETER BaseUri
        QBO API origin. Default production 'https://quickbooks.api.intuit.com'.
    .PARAMETER ModifiedAfter
        Optional ISO-8601 lower bound for incremental pulls (filters MetaData.LastUpdatedTime).
        Omit for a full backfill (the typical chart-of-accounts cadence — it is small).
    .EXAMPLE
        Get-ImperionQboExpenseAccount
    .EXAMPLE
        Get-ImperionQboExpenseAccount -ModifiedAfter (Get-Date).AddDays(-7).ToUniversalTime().ToString('o')
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

    # QBO's SQL-like query: expense-type accounts only (Classification = 'Expense' covers the
    # Expense / CostOfGoodsSold / OtherExpense AccountTypes), incremental on
    # MetaData.LastUpdatedTime when a bound is given. Clauses are single-quoted in the QBO query
    # grammar; the literal/timestamp are operator-supplied, never user input.
    $query = "SELECT * FROM Account WHERE Classification = 'Expense'"
    if ($ModifiedAfter) { $query += " AND MetaData.LastUpdatedTime > '$ModifiedAfter'" }

    $accounts = Invoke-ImperionQboRequest -AccessToken $accessToken -BaseUri $BaseUri `
        -RealmId $realmId -Query $query -EntityProperty 'Account'

    # First non-null of a chain of plausible source names (StrictMode-safe via Get-ImperionPropertyPath).
    $firstOf = {
        param($record, [string[]] $candidates)
        foreach ($candidate in $candidates) {
            $value = Get-ImperionPropertyPath -InputObject $record -Path $candidate
            if ($null -ne $value -and "$value" -ne '') { return $value }
        }
    }

    # Documented Account fields lead each chain; fallbacks tolerate casing/shape drift. The
    # column set matches issue #168: name, fully_qualified_name, account_type, account_sub_type,
    # active (+ created/updated time for provenance).
    $map = [ordered]@{
        name                 = { param($a) & $firstOf $a @('Name', 'name') }
        fully_qualified_name = { param($a) & $firstOf $a @('FullyQualifiedName', 'fullyQualifiedName') }
        account_type         = { param($a) & $firstOf $a @('AccountType', 'accountType') }
        account_sub_type     = { param($a) & $firstOf $a @('AccountSubType', 'accountSubType') }
        classification       = { param($a) & $firstOf $a @('Classification', 'classification') }
        active               = { param($a) & $firstOf $a @('Active', 'active') }
        created_time         = { param($a) & $firstOf $a @('MetaData.CreateTime', 'metaData.createTime') }
        last_updated_time    = { param($a) & $firstOf $a @('MetaData.LastUpdatedTime', 'metaData.lastUpdatedTime') }
    }

    $accounts | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'qbo' -TenantId $TenantId -ExternalIdProperty 'Id'
}
