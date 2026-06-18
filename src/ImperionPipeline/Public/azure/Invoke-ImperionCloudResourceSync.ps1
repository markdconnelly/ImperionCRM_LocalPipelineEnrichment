function Invoke-ImperionCloudResourceSync {
    <#
    .SYNOPSIS
        Sweep every registered client tenant's Azure ARM cloud resources into the CMDB
        cloud-asset bronze (the estate fan-out for epic #201 / frontend ADR-0103).
    .DESCRIPTION
        The scheduled entry point for the per-client Azure ARM cloud-resource inventory
        (ADR-0023). Instead of a hand-maintained env-var tenant list, it discovers the
        **whole estate** from the front-end-owned `account_tenant` registry (tenant_id ↔
        account_id, ADR-0051): every registered client tenant is swept, so adding/removing a
        managed tenant is a GUI action (Settings → Tenant mapping), not a config edit.

        Per tenant it composes `Get-ImperionCloudResource` → `Set-ImperionCloudResourceToBronze`
        over one shared DB connection. The enterprise app authenticates by certificate OR
        secret (frontend ADR-0103) via the standard token path. Per-tenant isolation is
        absolute (every row carries its owning tenant); a tenant that throws (no
        consent/credential, or the cloud_* bronze not yet applied) is logged and SKIPPED so
        one bad tenant never blocks the rest (fail closed, dormant-safe). Idempotent
        (change-detected upsert) — re-runs converge. Requires Initialize-ImperionContext.

        Dormant-safe fallback: with no rows in `account_tenant` the sweep runs the partner
        tenant only, so the task is safe to schedule before any client is onboarded.
    .PARAMETER ApiVersion
        ARM api-version for the subscription / resource-group / resource reads. Default 2022-09-01.
    .EXAMPLE
        Invoke-ImperionCloudResourceSync
    #>
    [CmdletBinding()]
    param(
        [string] $ApiVersion = '2022-09-01'
    )

    $started = Get-Date
    $conn = New-ImperionDbConnection
    try {
        # Discover the estate from the account_tenant registry (ADR-0051). The local pipeline
        # has read-only SELECT on it (frontend migration 0141). Distinct tenant ids only.
        $tenantRows = @(Invoke-ImperionDbQuery -Connection $conn -Sql @'
SELECT DISTINCT tenant_id FROM account_tenant WHERE tenant_id IS NOT NULL ORDER BY tenant_id
'@)
        $tenantIds = @($tenantRows | ForEach-Object { $_.tenant_id } | Where-Object { $_ })
        if ($tenantIds.Count -eq 0) {
            # No client tenants registered yet — partner tenant only (dormant-safe).
            Write-ImperionLog -Source 'azure_arm' -Message 'No client tenants in account_tenant; sweeping the partner tenant only.'
            $tenantIds = @($null)
        }

        $sweptTenants = 0
        $skippedTenants = 0
        foreach ($tenantId in $tenantIds) {
            try {
                if ($tenantId) {
                    Get-ImperionCloudResource -TenantId $tenantId -ApiVersion $ApiVersion | Set-ImperionCloudResourceToBronze -Connection $conn
                }
                else {
                    Get-ImperionCloudResource -ApiVersion $ApiVersion | Set-ImperionCloudResourceToBronze -Connection $conn
                }
                $sweptTenants++
            }
            catch {
                # Consent/credential gap or the cloud_* bronze not yet applied: log loudly and
                # continue to the next tenant. The next run converges once access/schema exist.
                $skippedTenants++
                Write-ImperionLog -Level Warn -Source 'azure_arm' -Message "Azure ARM cloud-resource sync skipped for tenant '$tenantId': $($_.Exception.Message)"
            }
        }

        Write-ImperionLog -Level Metric -Source 'azure_arm' -Message 'Azure ARM cloud-resource estate swept.' -Data @{
            tenants_registered = $tenantIds.Count
            tenants_swept      = $sweptTenants
            tenants_skipped    = $skippedTenants
            duration_s         = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
        }
    }
    finally {
        $conn.Dispose()
    }
}
