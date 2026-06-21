# m365/intune-apps - daily Intune managed-app inventory feed -> bronze
# (intune_managed_apps, issue #143 / front-end ImperionCRM #261: per app, unreduced; completes
# the drillable Intune asset detail alongside devices/compliance/configuration).
# Cadence: Daily (scheduled-tasks/README.md). Composes one get + one post; keep this short
# (CLAUDE.md §1). Single-tenant against the Imperion company tenant by default (Mark's
# 2026-06-11 authorization; GDAP fan-out deferred) - set IMPERION_M365_TENANT_IDS to a
# comma-separated list of customer tenant ids when fan-out resumes (per-tenant isolation:
# each row is stamped with its owning tenant).
#
# GATED: needs (1) the DeviceManagementApps.Read.All read grant admin-consented on the
# Onboarding app and (2) the intune_managed_apps bronze table from the front-end migration
# (schema handoff, ImperionCRM #261) - until both land the get/post fail loudly; the
# estate-sweep helper logs a Warn per tenant and continues so the schedule never crashes.
#
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion m365 intune apps' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\m365\intune-apps.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

Invoke-ImperionM365EstateSweep -Label 'Intune managed-apps' -PerTenant {
    param($TenantId)
    if ($TenantId) { Get-ImperionIntuneManagedApp -TenantId $TenantId | Set-ImperionIntuneManagedAppToBronze }
    else { Get-ImperionIntuneManagedApp | Set-ImperionIntuneManagedAppToBronze }
}
