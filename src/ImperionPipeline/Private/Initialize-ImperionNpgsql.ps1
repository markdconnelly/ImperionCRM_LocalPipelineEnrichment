function Initialize-ImperionNpgsql {
    <#
    .SYNOPSIS
        Ensure the Npgsql .NET assembly is loaded (private; called by Open-ImperionDbConnection).
    .DESCRIPTION
        Resolution order: (1) already-loaded Npgsql type; (2) an explicit path in
        $script:ImperionNpgsqlPath / $env:IMPERION_NPGSQL_DLL; (3) an Npgsql.dll shipped under
        the module's lib/ folder. Throws a clear, actionable error if none is found — see
        docs/deployment for installing Npgsql.
    #>
    [CmdletBinding()]
    param()

    if ('Npgsql.NpgsqlConnection' -as [type]) { return }

    $candidates = @(
        $script:ImperionNpgsqlPath,
        $env:IMPERION_NPGSQL_DLL,
        (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\Npgsql.dll')
    ) | Where-Object { $_ -and (Test-Path $_) }

    foreach ($dll in $candidates) {
        try { Add-Type -Path $dll -ErrorAction Stop; if ('Npgsql.NpgsqlConnection' -as [type]) { return } } catch { }
    }
    throw "Npgsql not available. Install it and set `$env:IMPERION_NPGSQL_DLL or drop Npgsql.dll in the module lib/ folder. See docs/deployment."
}
