#Requires -Version 7.2
<#
.SYNOPSIS
    Prove the unattended cert -> token -> Postgres chain end to end (CLAUDE.md §10 steps 2-3).
.DESCRIPTION
    A bootstrap smoke test, run ON the server (ideally as the gMSA/service identity, "whether
    logged on or not") AFTER the unattended identity is provisioned: certificate installed +
    ACL'd, SecretStore created + CMS-protected, Npgsql present, and the SP's Postgres role
    granted (front-end migration 0044). It exercises each link and reports PASS/FAIL per stage:

      1. Initialize-ImperionContext        — loads config + unlocks the SecretStore via the cert (CMS)
      2. Get-ImperionAccessToken (ossrdbms) — the cert SP mints a short-lived Postgres token (ADR-0003)
      3. Open-ImperionDbConnection          — token auth over TLS (proves firewall + role login)
      4. SELECT 1                            — basic round trip
      5. INSERT a throwaway row in a transaction, read it back, then ROLLBACK — proves scoped
         write with ZERO residue and no DELETE privilege required (the SP role has none by design).

    No data persists; nothing is logged that contains a secret. Read-only on success except for
    the rolled-back insert. This is operational tooling, not part of the module's tested surface
    (live DB I/O cannot be unit-tested, same as Open-ImperionDbConnection).
.PARAMETER ConfigPath
    Path to pipeline.config.psd1. Defaults to %ProgramData%\Imperion\pipeline.config.psd1.
.PARAMETER Table
    Bronze table to probe the write against. Default autotask_contracts (standard envelope).
.EXAMPLE
    pwsh -File build\Test-ImperionUnattendedChain.ps1
.EXAMPLE
    pwsh -File build\Test-ImperionUnattendedChain.ps1 -ConfigPath C:\ProgramData\Imperion\pipeline.config.psd1
#>
[CmdletBinding()]
param(
    [string] $ConfigPath = (Join-Path $env:ProgramData 'Imperion\pipeline.config.psd1'),
    [string] $Table = 'autotask_contracts'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$results = [System.Collections.Generic.List[object]]::new()
function Add-Stage { param([string] $Name, [bool] $Ok, [string] $Detail)
    $results.Add([pscustomobject]@{ Stage = $Name; Result = if ($Ok) { 'PASS' } else { 'FAIL' }; Detail = $Detail })
    $color = if ($Ok) { 'Green' } else { 'Red' }
    Write-Host ("[{0}] {1,-34} {2}" -f (if ($Ok) { 'PASS' } else { 'FAIL' }), $Name, $Detail) -ForegroundColor $color
}

$conn = $null
try {
    Import-Module ImperionPipeline -ErrorAction Stop

    # 1. Context + SecretStore unlock (cert -> CMS -> vault).
    Initialize-ImperionContext
    Add-Stage 'Initialize-ImperionContext' $true 'config loaded + SecretStore unlocked'

    if (-not (Test-Path $ConfigPath)) { throw "config not found at $ConfigPath" }
    $cfg = Import-PowerShellDataFile -Path $ConfigPath

    # 2. Cert SP mints a Postgres token.
    $token = Get-ImperionAccessToken -Resource 'https://ossrdbms-aad.database.windows.net/.default' `
        -TenantId $cfg.PartnerTenantId -ClientId $cfg.ClientId -CertThumbprint $cfg.CertThumbprint
    Add-Stage 'Get-ImperionAccessToken (ossrdbms)' ([bool]$token) ("token length {0}" -f $token.Length)

    # 3. Connect over TLS with the token (firewall + role login).
    $conn = Open-ImperionDbConnection -DbHost $cfg.Db.Host -Database $cfg.Db.Database `
        -Username $cfg.Db.Username -AccessToken $token -Port $cfg.Db.Port
    Add-Stage 'Open-ImperionDbConnection' ($conn.State -eq 'Open') ("connected to {0}/{1} as {2}" -f $cfg.Db.Host, $cfg.Db.Database, $cfg.Db.Username)

    # 4. Basic round trip.
    $one = Invoke-ImperionDbQuery -Connection $conn -Sql 'SELECT 1 AS ok'
    Add-Stage 'SELECT 1' ($one[0].ok -eq 1) 'round trip ok'

    # 5. Scoped write proof: INSERT a throwaway row inside a transaction, read it back, ROLLBACK.
    $marker = '__smoketest__'
    $extId = [guid]::NewGuid().ToString()
    $tx = $conn.BeginTransaction()
    try {
        $ins = $conn.CreateCommand(); $ins.Transaction = $tx
        $ins.CommandText = @"
INSERT INTO "$Table" (tenant_id, source, external_id, collected_at, raw_payload, content_hash)
VALUES (@t, @s, @e, @c, @p::jsonb, @h)
"@
        foreach ($kv in @{ t = $marker; s = $marker; e = $extId; c = (Get-Date).ToString('o'); p = '{"smoketest":true}'; h = 'smoketest' }.GetEnumerator()) {
            $pp = $ins.CreateParameter(); $pp.ParameterName = $kv.Key; $pp.Value = $kv.Value; $ins.Parameters.Add($pp) | Out-Null
        }
        $affected = $ins.ExecuteNonQuery(); $ins.Dispose()

        $check = $conn.CreateCommand(); $check.Transaction = $tx
        $check.CommandText = "SELECT count(*) AS n FROM `"$Table`" WHERE tenant_id=@t AND external_id=@e"
        foreach ($kv in @{ t = $marker; e = $extId }.GetEnumerator()) {
            $pp = $check.CreateParameter(); $pp.ParameterName = $kv.Key; $pp.Value = $kv.Value; $check.Parameters.Add($pp) | Out-Null
        }
        $readBack = [int]$check.ExecuteScalar(); $check.Dispose()
        Add-Stage 'INSERT + readback (in tx)' ($affected -eq 1 -and $readBack -eq 1) "inserted=$affected readback=$readBack into $Table"
    }
    finally {
        $tx.Rollback(); $tx.Dispose()   # zero residue — the throwaway row never persists
    }
    Add-Stage 'ROLLBACK (cleanup)' $true 'throwaway row discarded — no data written'
}
catch {
    Add-Stage 'EXCEPTION' $false $_.Exception.Message
}
finally {
    if ($conn) { $conn.Dispose() }
}

$failed = @($results | Where-Object Result -EQ 'FAIL').Count
Write-Host ''
Write-Host ("Chain smoke test: {0}/{1} stages passed." -f ($results.Count - $failed), $results.Count) -ForegroundColor (if ($failed) { 'Red' } else { 'Green' })
if ($failed) { exit 1 }
