# m365/devices - daily Intune managed-device pull -> bronze (m365_devices, ADR-0039 shape).
# Cadence: Daily (scheduled-tasks/README.md). Composes one get + one post; keep this short
# (CLAUDE.md §1). Defaults to the partner tenant; set IMPERION_M365_TENANT_IDS to a
# comma-separated list of customer tenant ids to fan out across GDAP tenants (per-tenant
# isolation: each row is stamped with its owning tenant; one bad tenant never blocks the
# rest - Invoke-ImperionM365EstateSweep, issue #266).
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion m365 devices' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\m365\devices.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

Invoke-ImperionM365EstateSweep -Label 'M365 devices' -PerTenant {
    param($TenantId)
    if ($TenantId) { Get-ImperionM365Device -TenantId $TenantId | Set-ImperionM365DeviceToBronze }
    else { Get-ImperionM365Device | Set-ImperionM365DeviceToBronze }
}
