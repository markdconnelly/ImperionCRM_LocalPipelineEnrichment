# azure/cloud-resources - daily per-client Azure ARM cloud-resource inventory -> bronze
# (cloud_subscriptions + cloud_resource_groups + cloud_resources; epic #201 / issue #216 /
# ADR-XXXX). The CMDB cloud-asset CI source: enumerates each consented client tenant's
# subscriptions, resource groups, and resources (read-only ARM, Reader) and lands them in the
# NEW per-client cloud_* bronze set. DISTINCT from the partner-tenant posture inventory
# (azure/inventory, ADR-0008 / azure_resources) — this is per-managed-client + CMDB-shaped.
#
# Cadence: Daily (scheduled-tasks/README.md) - cloud inventory drifts slowly; the
# change-detected upsert keeps re-runs cheap. Composes Get-ImperionCloudResource ->
# Set-ImperionCloudResourceToBronze per tenant (CLAUDE.md §1). Auth is the cert-SP ARM token
# (Reader, already held - NO new grant), fanned out per consented client tenant via the
# per-client onboarding app (CLAUDE.md §3, ADR-0018). Set IMPERION_M365_TENANT_IDS to a
# comma-separated list of client tenant ids; an empty list falls back to the partner tenant
# only (dormant-safe). Per-tenant isolation: each row is stamped with its owning tenant; a
# tenant that throws (no consent/credential) is logged and skipped (fail closed).
#
# GATED: until the front-end cloud_* migration is applied to prod the post fails loudly; the
# per-tenant catch below logs a Warn and continues so the schedule never crashes (idempotent,
# change-detected upsert — the next run converges once the table exists).
#
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion azure cloud-resources' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\azure\cloud-resources.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

$tenantIds = @($env:IMPERION_M365_TENANT_IDS -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($tenantIds.Count -eq 0) {
    # Dormant-safe fallback: no consented client tenants configured -> partner tenant only.
    $tenantIds = @($null)
}

foreach ($tenantId in $tenantIds) {
    try {
        if ($tenantId) {
            Get-ImperionCloudResource -TenantId $tenantId | Set-ImperionCloudResourceToBronze
        }
        else {
            Get-ImperionCloudResource | Set-ImperionCloudResourceToBronze
        }
    }
    catch {
        # Schema/identity/consent gate: log loudly and continue to the next tenant. The
        # operator lands the front-end cloud_* prod apply (and per-tenant consent) and the
        # next run converges (idempotent, change-detected upsert).
        Write-ImperionLog -Level Warn -Source 'azure_arm' -Message "Azure ARM cloud-resource sync skipped for tenant '$tenantId': $($_.Exception.Message)"
    }
}
