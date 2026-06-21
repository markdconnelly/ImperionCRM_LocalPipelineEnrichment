# m365/entra-domains - daily tenant-hygiene domain pull -> bronze
# (entra_domains, issue #142 / front-end schema issue #260).
# Cadence: Daily (scheduled-tasks/README.md) - domains are slow-changing; the
# change-detected upsert keeps re-runs cheap. Composes one get + one post; keep this short
# (CLAUDE.md §1). Auth is the module's cert-SP Graph token (Domain.Read.All, read-only,
# part of the read-only-by-default grant); single-tenant against the Imperion company
# tenant by default - set IMPERION_M365_TENANT_IDS for GDAP fan-out (per-tenant isolation:
# each row is stamped with its owning tenant).
#
# GATED: until the front-end entra_domains migration (#260) is applied to prod the post
# fails loudly; the estate-sweep helper logs a Warn per tenant and continues so the schedule
# never crashes.
#
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion m365 entra-domains' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\m365\entra-domains.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

Invoke-ImperionM365EstateSweep -Label 'Entra domains' -PerTenant {
    param($TenantId)
    if ($TenantId) { Get-ImperionEntraDomain -TenantId $TenantId | Set-ImperionEntraDomainToBronze }
    else { Get-ImperionEntraDomain | Set-ImperionEntraDomainToBronze }
}
