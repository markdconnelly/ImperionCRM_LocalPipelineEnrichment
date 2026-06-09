function Invoke-ImperionBronzeUpsert {
    <#
    .SYNOPSIS
        Upsert flat rows into a bronze table with built-in change detection.
    .DESCRIPTION
        Batched, parameterized INSERT ... ON CONFLICT (key columns) DO UPDATE ... WHERE the
        stored content_hash IS DISTINCT FROM the incoming one. Unchanged rows are not
        rewritten (docs/operations/change-detection.md). Returns a tally
        { scanned; inserted; updated; unchanged }. The table must already exist (schema is
        owned by the front-end repo, ADR-0005) — this never creates it.
    .PARAMETER Connection
        Open Npgsql connection.
    .PARAMETER Table
        Target bronze table name.
    .PARAMETER Rows
        Array of flat PSCustomObjects (from ConvertTo-ImperionFlatObject) sharing the same columns.
    .PARAMETER KeyColumns
        Conflict-target columns (must back a unique/primary key). Default tenant_id, source, external_id.
    .PARAMETER JsonColumns
        Columns cast to jsonb on insert. Default raw_payload.
    .PARAMETER NoChangeDetect
        Omit the `content_hash IS DISTINCT FROM` guard. Use for tables that have no
        content_hash column — e.g. the ADR-0039 per-source shape (televy_reports,
        darkwebid_exposures) keyed on external_ref, where change is resolved in the merge,
        not at the bronze gate. Every conflicting row is then updated (none counted unchanged).
    .PARAMETER BatchSize
        Rows per statement. Default 500.
    .EXAMPLE
        $tally = Invoke-ImperionBronzeUpsert -Connection $c -Table m365_service_principals -Rows $flat
    .EXAMPLE
        # ADR-0039 per-source shape (no content_hash column):
        $tally = Invoke-ImperionBronzeUpsert -Connection $c -Table televy_reports -Rows $projected `
            -KeyColumns external_ref -JsonColumns payload_bronze -NoChangeDetect
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] $Connection,
        [Parameter(Mandatory)][string] $Table,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Rows,
        [string[]] $KeyColumns = @('tenant_id', 'source', 'external_id'),
        [string[]] $JsonColumns = @('raw_payload'),
        [switch] $NoChangeDetect,
        [int] $BatchSize = 500
    )

    $tally = [ordered]@{ scanned = $Rows.Count; inserted = 0; updated = 0; unchanged = 0 }
    if ($Rows.Count -eq 0) { return [pscustomobject]$tally }

    $columns = $Rows[0].PSObject.Properties.Name
    $nonKey = $columns | Where-Object { $_ -notin $KeyColumns }
    $quotedCols = ($columns | ForEach-Object { '"' + $_ + '"' }) -join ', '
    $conflict = ($KeyColumns | ForEach-Object { '"' + $_ + '"' }) -join ', '
    $setClause = ($nonKey | ForEach-Object { '"{0}" = EXCLUDED."{0}"' -f $_ }) -join ', '

    for ($offset = 0; $offset -lt $Rows.Count; $offset += $BatchSize) {
        $batch = $Rows[$offset..([math]::Min($offset + $BatchSize, $Rows.Count) - 1)]

        $cmd = $Connection.CreateCommand()
        $valueGroups = [System.Collections.Generic.List[string]]::new()
        for ($r = 0; $r -lt $batch.Count; $r++) {
            $placeholders = for ($ci = 0; $ci -lt $columns.Count; $ci++) {
                $col = $columns[$ci]
                $pname = "@p${r}_${ci}"
                $param = $cmd.CreateParameter(); $param.ParameterName = $pname
                $val = $batch[$r].$col
                $param.Value = if ($null -eq $val) { [DBNull]::Value } else { $val }
                $cmd.Parameters.Add($param) | Out-Null
                if ($col -in $JsonColumns) { "$pname::jsonb" } else { $pname }
            }
            $valueGroups.Add('(' + ($placeholders -join ', ') + ')')
        }

        $changeGuard = if ($NoChangeDetect) { '' } else { "`nWHERE `"$Table`".content_hash IS DISTINCT FROM EXCLUDED.content_hash" }
        $cmd.CommandText = @"
INSERT INTO "$Table" ($quotedCols)
VALUES $($valueGroups -join ', ')
ON CONFLICT ($conflict) DO UPDATE SET $setClause$changeGuard
RETURNING (xmax = 0) AS inserted;
"@

        $reader = $cmd.ExecuteReader()
        try {
            $returned = 0
            while ($reader.Read()) {
                $returned++
                if ($reader.GetBoolean(0)) { $tally.inserted++ } else { $tally.updated++ }
            }
            $tally.unchanged += ($batch.Count - $returned)
        }
        finally { $reader.Dispose(); $cmd.Dispose() }
    }

    return [pscustomobject]$tally
}
