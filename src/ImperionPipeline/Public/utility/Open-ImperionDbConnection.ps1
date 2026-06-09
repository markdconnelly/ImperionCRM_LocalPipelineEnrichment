function Open-ImperionDbConnection {
    <#
    .SYNOPSIS
        Open an Npgsql connection to the shared Azure PostgreSQL using a short-lived Entra token (ADR-0003).
    .DESCRIPTION
        No stored password: the AAD access token (resource
        https://ossrdbms-aad.database.windows.net/.default) is used as the password, with the
        SP's Entra principal name as the username, over TLS. Caller disposes the connection.
    .PARAMETER DbHost
        PostgreSQL host (e.g. imperioncrm.postgres.database.azure.com).
    .PARAMETER Database
        Database name.
    .PARAMETER Username
        Entra principal name of the service principal's Postgres role.
    .PARAMETER AccessToken
        AAD token for the ossrdbms resource (from Get-ImperionAccessToken).
    .PARAMETER Port
        Defaults to 5432.
    .EXAMPLE
        $conn = Open-ImperionDbConnection -DbHost $h -Database imperion -Username $u -AccessToken $pgTok
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)][string] $DbHost,
        [Parameter(Mandatory)][string] $Database,
        [Parameter(Mandatory)][string] $Username,
        [Parameter(Mandatory)][string] $AccessToken,
        [int] $Port = 5432
    )

    Initialize-ImperionNpgsql

    $builder = [Npgsql.NpgsqlConnectionStringBuilder]::new()
    $builder.Host = $DbHost
    $builder.Port = $Port
    $builder.Database = $Database
    $builder.Username = $Username
    $builder.Password = $AccessToken
    $builder.SslMode = [Npgsql.SslMode]::Require
    $builder.Timeout = 30
    $builder.CommandTimeout = 300

    $conn = [Npgsql.NpgsqlConnection]::new($builder.ConnectionString)
    $conn.Open()
    return $conn
}
