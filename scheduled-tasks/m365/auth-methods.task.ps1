# m365/auth-methods - daily per-user MFA registration pull -> bronze
# (entra_auth_methods, issue #140 / front-end migration 0077 + ADR-0051).
# Cadence: Daily (scheduled-tasks/README.md) - registration state is slow-changing; the
# change-detected upsert keeps re-runs cheap. Composes one get + one post; keep this short
# (CLAUDE.md §1). Auth is the module's cert-SP Graph token
# (UserAuthenticationMethod.Read.All, already admin-consented); single-tenant against the
# Imperion company tenant by default - set IMPERION_M365_TENANT_IDS for fan-out
# (per-tenant isolation: each row is stamped with its owning tenant).
#
# GATED: until front-end migration 0077 is applied to prod the post fails loudly; the
# estate-sweep helper logs a Warn per tenant and continues so the schedule never crashes.
#
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion m365 auth-methods' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\m365\auth-methods.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

Invoke-ImperionM365EstateSweep -Label 'Entra auth-methods' -PerTenant {
    param($TenantId)
    if ($TenantId) { Get-ImperionEntraAuthMethod -TenantId $TenantId | Set-ImperionEntraAuthMethodToBronze }
    else { Get-ImperionEntraAuthMethod | Set-ImperionEntraAuthMethodToBronze }
}
