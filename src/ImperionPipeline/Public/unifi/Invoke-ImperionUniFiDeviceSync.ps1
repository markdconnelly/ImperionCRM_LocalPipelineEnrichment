function Invoke-ImperionUniFiDeviceSync {
    <#
    .SYNOPSIS
        Sweep every registered managed-client UniFi console into the unifi_devices bronze,
        resolving each console's API key from the credential registry (multi-console — #259).
    .DESCRIPTION
        The scheduled entry point for the per-client UniFi device inventory. Supersedes the
        single-key, single-console shape of Get-ImperionUniFiDevice (#73): instead of a
        company-wide key passed in by the caller, it discovers the **whole UniFi estate** from
        the front-end-owned `connection` credential registry (ADR-0103 / backend #229) and
        resolves each console's own API key per row.

        Per active client UniFi `connection` row it:
          1. resolves the console's API key from the registry via
             Resolve-ImperionTenantCredential -Provider unifi -FailClosed -> @{ ApiKey };
          2. reads the non-secret console config off `provider_config` (jsonb, FE migration
             0151 / backend #233): `connectionType` (console|cloud, which API family) and
             `controllerHost` (the on-prem Network Integration API host, console only);
          3. composes Get-ImperionUniFiDevice -> Set-ImperionUniFiDeviceToBronze over one
             shared DB connection, stamping the owning tenant on every row.

        Per-console isolation is absolute: every bronze row carries its owning tenant, and a
        console that throws (no usable credential, missing/invalid provider_config, the
        unifi_devices bronze not yet applied, or an unreachable controller) is logged and
        SKIPPED so one bad console never blocks the rest (fail closed). Idempotent
        (change-detected upsert) — re-runs converge. Requires Initialize-ImperionContext.

        Dormant-safe: with no active client UniFi rows the sweep logs and no-ops, so the task
        is safe to schedule before any console is registered.

        SECRET HANDLING: the API key never leaves the resolver splat — it is read by reference
        from Key Vault, handed straight to Get-ImperionUniFiDevice, and never logged or
        persisted here (CLAUDE.md §8/§9). `provider_config` is non-secret config only.
    .EXAMPLE
        Invoke-ImperionUniFiDeviceSync
    #>
    [CmdletBinding()]
    param()

    $started = Get-Date
    $conn = New-ImperionDbConnection
    try {
        # Discover the UniFi estate from the credential registry (ADR-0103). One account may
        # map MANY consoles (many rows); external_account_id is the per-console natural key.
        $consoleRows = @(Invoke-ImperionDbQuery -Connection $conn -Sql @'
SELECT account_id, external_account_id, provider_config
FROM connection
WHERE scope = 'client' AND provider = 'unifi' AND status = 'active'
  AND external_account_id IS NOT NULL
ORDER BY account_id, external_account_id
'@)

        if ($consoleRows.Count -eq 0) {
            # No client consoles registered yet — nothing to sweep (dormant-safe).
            Write-ImperionLog -Source 'unifi' -Message 'No active client UniFi consoles registered; nothing to sweep.'
            return
        }

        $sweptConsoles = 0
        $skippedConsoles = 0
        foreach ($row in $consoleRows) {
            $consoleId = $row.external_account_id
            try {
                # Resolve THIS console's API key from the registry. Fail-closed: a row with no
                # usable credential (no consent / empty Key Vault secret) throws -> skip.
                $cred = Resolve-ImperionTenantCredential -Connection $conn -AccountId $row.account_id `
                    -Provider 'unifi' -FailClosed
                if (-not $cred.ApiKey) { throw "resolver returned no ApiKey for console '$consoleId'." }

                # Non-secret console config (jsonb -> object). Missing/blank connectionType is a
                # registration error: skip the console rather than guess an API family.
                $config = if ($row.provider_config) { $row.provider_config | ConvertFrom-Json } else { $null }
                $connectionType = $config.connectionType
                if (-not $connectionType) {
                    throw "console '$consoleId' has no provider_config.connectionType (re-register via the GUI)."
                }

                # Owning-tenant isolation key: prefer the account's Microsoft tenant (so UniFi
                # rows align with the client's other data under one tenant_id), else fall back to
                # the account id so the stamp is always present and never the partner tenant.
                $tenantId = Resolve-ImperionAccountTenant -Connection $conn -AccountId $row.account_id

                $deviceArgs = @{
                    ApiKey         = $cred.ApiKey
                    ConnectionType = $connectionType
                    TenantId       = $tenantId
                }
                if ($connectionType -eq 'console') { $deviceArgs.ControllerHost = $config.controllerHost }

                Get-ImperionUniFiDevice @deviceArgs | Set-ImperionUniFiDeviceToBronze -Connection $conn
                $sweptConsoles++
            }
            catch {
                # Credential/config gap or an unreachable/unmigrated target: log loudly and
                # continue to the next console. The next run converges once it is fixed.
                $skippedConsoles++
                Write-ImperionLog -Level Warn -Source 'unifi' -Message "UniFi device sync skipped for console '$consoleId': $($_.Exception.Message)"
            }
        }

        Write-ImperionLog -Level Metric -Source 'unifi' -Message 'UniFi console estate swept.' -Data @{
            consoles_registered = $consoleRows.Count
            consoles_swept      = $sweptConsoles
            consoles_skipped    = $skippedConsoles
            duration_s          = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
        }
    }
    finally {
        $conn.Dispose()
    }
}
