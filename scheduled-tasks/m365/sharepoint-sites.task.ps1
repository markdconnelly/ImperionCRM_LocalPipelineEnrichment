# m365/sharepoint-sites - daily SharePoint site inventory pull -> bronze
# (sharepoint_sites, issue #137 / front-end migration 0078 + issue #255).
# Cadence: Daily (scheduled-tasks/README.md) - site inventory is slow-changing; the
# change-detected upsert keeps re-runs cheap. Composes one get + one post; keep this short
# (CLAUDE.md §1). Auth is the module's cert-SP Graph token (Sites.Read.All, already
# admin-consented; Files.Read.All is PRUNED - this task touches site METADATA only, never
# /drives or /items); single-tenant against the Imperion company tenant by default - set
# IMPERION_M365_TENANT_IDS for fan-out (per-tenant isolation: each row is stamped with its
# owning tenant).
#
# GATED: until front-end migration 0078 is applied to prod the post fails loudly; the
# catch below logs a Warn and exits cleanly so the schedule never crashes.
#
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion m365 sharepoint-sites' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\m365\sharepoint-sites.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

try {
    $tenantIds = @($env:IMPERION_M365_TENANT_IDS -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($tenantIds.Count -eq 0) {
        Get-ImperionSharePointSite | Set-ImperionSharePointSiteToBronze
    }
    else {
        foreach ($tenantId in $tenantIds) {
            Get-ImperionSharePointSite -TenantId $tenantId | Set-ImperionSharePointSiteToBronze
        }
    }
}
catch {
    # Schema/permission gate: log loudly and exit; the operator lands the 0078 prod apply
    # and the next run converges (idempotent, change-detected upsert).
    Write-ImperionLog -Level Warn -Source 'm365' -Message "SharePoint site inventory sync skipped: $($_.Exception.Message)"
}
