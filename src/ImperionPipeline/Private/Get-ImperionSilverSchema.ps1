function Get-ImperionSilverSchema {
    <#
    .SYNOPSIS
        Introspect the live column NAMES of a silver-tier relation from information_schema.
    .DESCRIPTION
        Reads ONLY catalog metadata (column names + ordinal) for one relation — never any row,
        never any value. This is deliberately the narrowest possible read: the OKF bundle is a
        PII-free meaning layer (ADR-0086 / CLAUDE.md sections 8 & 11), so the drift agent must
        learn the SHAPE of a table without ever touching its DATA. information_schema.columns
        covers both base tables and views, so silver views are introspected the same way.

        Returns the ordered list of column-name strings, or @() when the relation does not exist
        (so the caller can classify the concept as 'orphaned-concept' rather than crashing).
    .PARAMETER Connection
        An open Npgsql connection (reused across relations by the caller).
    .PARAMETER Relation
        Unqualified relation name in the public schema (e.g. 'account').
    .EXAMPLE
        Get-ImperionSilverSchema -Connection $c -Relation 'expense_item'
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)] $Connection,
        [Parameter(Mandatory)][string] $Relation
    )

    $sql = @'
SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = @rel
ORDER BY ordinal_position
'@
    $rows = Invoke-ImperionDbQuery -Connection $Connection -Sql $sql -Parameters @{ rel = $Relation }
    return [string[]]@($rows | ForEach-Object { [string]$_.column_name })
}
