# m365/users - daily M365 (Entra) user pull -> bronze (m365_contacts, ADR-0039 shape).
# Cadence: Daily (scheduled-tasks/README.md). Composes one get + one post; keep this short
# (CLAUDE.md §1). Defaults to the partner tenant; set IMPERION_M365_TENANT_IDS to a
# comma-separated list of customer tenant ids to fan out across GDAP tenants (per-tenant
# isolation: each row is stamped with its owning tenant; one bad tenant never blocks the
# rest - Invoke-ImperionM365EstateSweep, issue #266).
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion m365 users' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\m365\users.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

Invoke-ImperionM365EstateSweep -Label 'M365 users' -PerTenant {
    param($TenantId)
    if ($TenantId) { Get-ImperionM365User -TenantId $TenantId | Set-ImperionM365UserToBronze }
    else { Get-ImperionM365User | Set-ImperionM365UserToBronze }
}
