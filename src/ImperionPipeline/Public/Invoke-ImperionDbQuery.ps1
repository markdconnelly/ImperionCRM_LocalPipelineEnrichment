function Invoke-ImperionDbQuery {
    <#
    .SYNOPSIS
        Run a parameterized SELECT and return rows as PSCustomObjects.
    .PARAMETER Connection
        An open Npgsql connection from Open-ImperionDbConnection.
    .PARAMETER Sql
        SQL text with @named parameters.
    .PARAMETER Parameters
        Hashtable of @name -> value.
    .EXAMPLE
        Invoke-ImperionDbQuery -Connection $c -Sql 'SELECT external_id, content_hash FROM m365_service_principals WHERE source=@s' -Parameters @{ s='m365' }
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)] $Connection,
        [Parameter(Mandatory)][string] $Sql,
        [hashtable] $Parameters = @{}
    )

    $cmd = $Connection.CreateCommand()
    $cmd.CommandText = $Sql
    foreach ($k in $Parameters.Keys) {
        $p = $cmd.CreateParameter(); $p.ParameterName = $k
        $p.Value = if ($null -eq $Parameters[$k]) { [DBNull]::Value } else { $Parameters[$k] }
        $cmd.Parameters.Add($p) | Out-Null
    }

    $reader = $cmd.ExecuteReader()
    try {
        $rows = [System.Collections.Generic.List[object]]::new()
        while ($reader.Read()) {
            $o = [ordered]@{}
            for ($i = 0; $i -lt $reader.FieldCount; $i++) {
                $name = $reader.GetName($i)
                $o[$name] = if ($reader.IsDBNull($i)) { $null } else { $reader.GetValue($i) }
            }
            $rows.Add([pscustomobject]$o)
        }
        return $rows.ToArray()
    }
    finally { $reader.Dispose(); $cmd.Dispose() }
}
