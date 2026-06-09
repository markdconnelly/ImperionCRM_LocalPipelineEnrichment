function Invoke-ImperionDbNonQuery {
    <#
    .SYNOPSIS
        Execute a parameterized non-query (INSERT/UPDATE/DDL) and return rows affected.
    .PARAMETER Connection
        An open Npgsql connection.
    .PARAMETER Sql
        SQL text with @named parameters.
    .PARAMETER Parameters
        Hashtable of @name -> value.
    .EXAMPLE
        Invoke-ImperionDbNonQuery -Connection $c -Sql 'DELETE FROM itglue_relationship WHERE from_type=@t AND from_id=@id' -Parameters @{ t='configurations'; id='123' }
    #>
    [CmdletBinding()]
    [OutputType([int])]
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
    try { return $cmd.ExecuteNonQuery() }
    finally { $cmd.Dispose() }
}
