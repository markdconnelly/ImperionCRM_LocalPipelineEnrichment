# m365/entra-role-assignments - daily tenant-hygiene directory role-assignment pull -> bronze
# (entra_role_assignments, issue #142 / front-end schema issue #260).
# Cadence: Daily (scheduled-tasks/README.md) - privileged membership is slow-changing but
# security-relevant; the change-detected upsert keeps re-runs cheap. Composes one get + one
# post; keep this short (CLAUDE.md §1). Auth is the module's cert-SP Graph token
# (RoleManagement.Read.Directory, read-only, part of the read-only-by-default grant);
# single-tenant against the Imperion company tenant by default - set IMPERION_M365_TENANT_IDS
# for GDAP fan-out (per-tenant isolation: each row is stamped with its owning tenant).
# role_display_name + principal_type are the hygiene signal a benchmark reads.
#
# GATED: until the front-end entra_role_assignments migration (#260) is applied to prod the
# post fails loudly; the estate-sweep helper logs a Warn per tenant and continues so the
# schedule never crashes.
#
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion m365 entra-role-assignments' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\m365\entra-role-assignments.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

Invoke-ImperionM365EstateSweep -Label 'Entra role-assignments' -PerTenant {
    param($TenantId)
    if ($TenantId) { Get-ImperionEntraRoleAssignment -TenantId $TenantId | Set-ImperionEntraRoleAssignmentToBronze }
    else { Get-ImperionEntraRoleAssignment | Set-ImperionEntraRoleAssignmentToBronze }
}
