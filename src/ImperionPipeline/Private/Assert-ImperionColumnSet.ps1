function Assert-ImperionColumnSet {
    <#
    .SYNOPSIS
        Fail fast when a collector's declared -ColumnSet has drifted from the live table.
    .DESCRIPTION
        The -ColumnSet drift guard (#427). Collectors written before a front-end bronze
        migration landed can declare a column the live table never got (or lost) — and
        that mismatch used to surface only as an opaque Postgres insert failure deep in
        Invoke-ImperionBronzeUpsert. The repo contract is "fail loudly if an expected
        table/column is missing" (CLAUDE.md §6), at the RIGHT layer: before the write,
        with an error that names the table and the missing columns.

        Introspects the live column names via Get-ImperionSilverSchema (catalog metadata
        only — information_schema.columns, never row data; it covers bronze base tables
        the same as silver views) and throws when the table is absent or any declared
        column is missing. Comparison is case-insensitive, matching PowerShell semantics
        and Postgres's lower-cased unquoted identifiers. Schema stays front-end-owned
        (ADR-0005): this guard never creates or alters anything — the fix for drift is
        reconciling the collector or proposing a front-end migration.
    .PARAMETER Connection
        Open Npgsql connection (reused; never opened or disposed here).
    .PARAMETER Table
        Target bronze table name (unqualified, public schema).
    .PARAMETER ColumnSet
        The collector's declared column set to validate against the live table.
    .EXAMPLE
        Assert-ImperionColumnSet -Connection $c -Table 'azure_resources' -ColumnSet $columns
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Connection,
        [Parameter(Mandatory)][string] $Table,
        [Parameter(Mandatory)][string[]] $ColumnSet
    )

    # @() guard: PowerShell unwraps a 0/1-element function output, and StrictMode
    # (module-wide, Latest) then rejects .Count on the scalar/$null result.
    $liveColumns = @(Get-ImperionSilverSchema -Connection $Connection -Relation $Table)
    if ($liveColumns.Count -eq 0) {
        throw ("ColumnSet drift guard: table '{0}' does not exist in the live schema. " +
            'Bronze tables are owned by the front-end repo (ADR-0005) - propose the migration there before running this collector.') -f $Table
    }

    $missingColumns = @($ColumnSet | Where-Object { $_ -notin $liveColumns })
    if ($missingColumns.Count -gt 0) {
        throw ("ColumnSet drift guard: table '{0}' is missing declared column(s): {1}. " +
            "The collector's -ColumnSet no longer matches the live schema - reconcile the collector " +
            'or propose a front-end migration (ADR-0005). Live columns: {2}.') -f `
            $Table, ($missingColumns -join ', '), ($liveColumns -join ', ')
    }
}
