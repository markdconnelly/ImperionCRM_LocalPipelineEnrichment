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
# estate-sweep helper logs a Warn per tenant and continues so the schedule never crashes.
#
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion m365 sharepoint-sites' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\m365\sharepoint-sites.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

Invoke-ImperionM365EstateSweep -Label 'SharePoint site inventory' -PerTenant {
    param($TenantId)
    if ($TenantId) { Get-ImperionSharePointSite -TenantId $TenantId | Set-ImperionSharePointSiteToBronze }
    else { Get-ImperionSharePointSite | Set-ImperionSharePointSiteToBronze }
}
