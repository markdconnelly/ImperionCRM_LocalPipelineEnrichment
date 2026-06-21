# m365/intune-devices - daily Intune managedDevices device-compliance feed -> bronze
# (intune_managed_devices, issue #75 / front-end ADR-0051 decision 6: per device, unreduced;
# the ONLY source of device-level posture indicators - never proxied from tenant level).
# Cadence: Daily (scheduled-tasks/README.md). Composes one get + one post; keep this short
# (CLAUDE.md §1). Single-tenant against the Imperion company tenant by default (Mark's
# 2026-06-11 authorization; GDAP fan-out deferred) - set IMPERION_M365_TENANT_IDS to a
# comma-separated list of customer tenant ids when fan-out resumes (per-tenant isolation:
# each row is stamped with its owning tenant).
#
# GATED: the intune_managed_devices bronze table needs the front-end migration (schema
# handoff, issue #75 comment) - until it lands the post fails loudly; the estate-sweep
# helper logs a Warn per tenant and continues so the schedule never crashes.
#
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion m365 intune devices' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\m365\intune-devices.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

Invoke-ImperionM365EstateSweep -Label 'Intune managed-devices' -PerTenant {
    param($TenantId)
    if ($TenantId) { Get-ImperionM365Device -TenantId $TenantId | Set-ImperionIntuneManagedDeviceToBronze }
    else { Get-ImperionM365Device | Set-ImperionIntuneManagedDeviceToBronze }
}
