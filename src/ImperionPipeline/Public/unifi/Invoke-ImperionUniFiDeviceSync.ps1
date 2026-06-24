function Invoke-ImperionUniFiDeviceSync {
    <#
    .SYNOPSIS
        Sweep the WHOLE UniFi estate into the unifi_devices bronze with ONE company Site Manager
        key, mapping each device's site to its owning account (#321, company-scope remodel).
    .DESCRIPTION
        The scheduled entry point for UniFi device inventory. UniFi is a COMPANY-scope cloud
        connector (FE #1278 / backend #386, ADR-0122): the cloud Site Manager API key is MSP-wide,
        so ONE key (`conn-company-unifi`) enumerates every client's sites and devices. This
        SUPERSEDES the per-console fan-out (#259) that resolved a separate key per client
        `connection` row — that path is retired (it logged "No active client UniFi consoles
        registered" because UniFi is no longer registered per client).

        It:
          1. resolves the company Site Manager key from the credential registry via
             Resolve-ImperionCompanyCredential -Provider unifi -Field apiKey (ADR-0103 / #319);
          2. reads the GUI-curated site->account mappings from `entity_xref` (entity_type
             'account', source_system 'unifi', match_method 'manual' — keyed on the site name,
             the same `site` column the FE client-mapping unit list shows);
          3. composes Get-ImperionUniFiDevice -> Set-ImperionUniFiDeviceToBronze over one shared
             DB connection. Each device's `tenant_id` is stamped with its mapped account id (or the
             all-zero sentinel when its site is not mapped yet) so the co-located merge
             (Invoke-ImperionUniFiMerge, #284) resolves it directly.

        Idempotent (change-detected upsert) — re-runs converge. A device whose site is unmapped
        still lands in bronze (sentinel tenant) so the GUI surfaces the site for mapping; once
        mapped, the next run re-stamps it with the real account.

        Dormant-safe: with no active company `unifi` connection (key not entered) the sweep logs
        and no-ops, so the task is safe to schedule before the key is registered.

        SECRET HANDLING: the API key never leaves the resolver result — it is read by reference
        from Key Vault, handed straight to Get-ImperionUniFiDevice, and never logged or persisted
        (CLAUDE.md §8/§9). Requires Initialize-ImperionContext.
    .EXAMPLE
        Invoke-ImperionUniFiDeviceSync
    #>
    [CmdletBinding()]
    param()

    $started = Get-Date
    $conn = New-ImperionDbConnection
    try {
        # 1) The ONE company Site Manager key. Dormant-safe: not connected -> log + no-op.
        $apiKey = Resolve-ImperionCompanyCredential -Provider 'unifi' -Field 'apiKey' -Connection $conn
        if (-not $apiKey) {
            Write-ImperionLog -Source 'unifi' -Message 'No active company UniFi Site Manager key; nothing to sweep.'
            return
        }

        # 2) GUI-curated site->account mappings (the manual entity_xref spine, FE migration 0160).
        # Keyed on the site name (the FE client-mapping unit key for unifi), value = account id.
        $mappingRows = @(Invoke-ImperionDbQuery -Connection $conn -Sql @'
SELECT source_key, internal_entity_id::text AS account_id
FROM entity_xref
WHERE entity_type = 'account' AND source_system = 'unifi' AND match_method = 'manual'
'@)
        $siteAccountMap = @{}
        foreach ($mapping in $mappingRows) {
            if ($mapping.source_key) { $siteAccountMap[[string]$mapping.source_key] = [string]$mapping.account_id }
        }

        # 3) Pull the whole estate with the one key, account-stamped per site, then write bronze.
        $rows = @(Get-ImperionUniFiDevice -ApiKey $apiKey -SiteAccountMap $siteAccountMap)
        if ($rows.Count -gt 0) { $rows | Set-ImperionUniFiDeviceToBronze -Connection $conn }

        $unmappedTenant = '00000000-0000-0000-0000-000000000000'
        $mapped = @($rows | Where-Object { [string]$_.tenant_id -ne $unmappedTenant }).Count
        Write-ImperionLog -Level Metric -Source 'unifi' -Message 'UniFi estate swept (company Site Manager key).' -Data @{
            devices      = $rows.Count
            mapped       = $mapped
            unmapped     = ($rows.Count - $mapped)
            sites_mapped = $siteAccountMap.Count
            duration_s   = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
        }
    }
    finally {
        $conn.Dispose()
    }
}
