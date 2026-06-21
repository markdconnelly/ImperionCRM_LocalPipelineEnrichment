# m365/entra-groups - daily Entra/M365 group inventory pull -> bronze
# (m365_groups, issue #150 split from #139 / front-end migration 0079 + issue #257).
# Cadence: Daily (scheduled-tasks/README.md) - group inventory is slow-changing; the
# change-detected upsert keeps re-runs cheap. Composes one get + one post; keep this short
# (CLAUDE.md §1). Auth is the module's cert-SP Graph token (Group.Read.All, read-only);
# single-tenant against the Imperion company tenant by default - set IMPERION_M365_TENANT_IDS
# for fan-out (per-tenant isolation: each row is stamped with its owning tenant).
#
# Membership EDGES are a separate task (entra-group-members, issue #139).
#
# GATED: migration 0079 is applied to prod (2026-06-12); were m365_groups ever absent the
# post fails loudly and the estate-sweep helper logs a Warn per tenant and continues so the
# schedule never crashes.
#
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion m365 entra-groups' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\m365\entra-groups.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

Invoke-ImperionM365EstateSweep -Label 'Entra group inventory' -PerTenant {
    param($TenantId)
    if ($TenantId) { Get-ImperionM365Group -TenantId $TenantId | Set-ImperionM365GroupToBronze }
    else { Get-ImperionM365Group | Set-ImperionM365GroupToBronze }
}
