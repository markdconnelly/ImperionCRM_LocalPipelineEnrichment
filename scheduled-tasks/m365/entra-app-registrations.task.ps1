# m365/entra-app-registrations - daily tenant-hygiene app-registration pull -> bronze
# (entra_app_registrations, issue #142 / front-end schema issue #260).
# Cadence: Daily (scheduled-tasks/README.md) - registrations are slow-changing; the
# change-detected upsert keeps re-runs cheap. Composes one get + one post; keep this short
# (CLAUDE.md §1). Auth is the module's cert-SP Graph token (Application.Read.All, read-only,
# part of the read-only-by-default grant); single-tenant against the Imperion company tenant
# by default - set IMPERION_M365_TENANT_IDS for GDAP fan-out (per-tenant isolation: each row
# is stamped with its owning tenant). Credential counts + nearest expiry are the hygiene
# signal a benchmark reads.
#
# GATED: until the front-end entra_app_registrations migration (#260) is applied to prod the
# post fails loudly; the catch below logs a Warn and exits cleanly so the schedule never
# crashes.
#
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion m365 entra-app-registrations' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\m365\entra-app-registrations.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

try {
    $tenantIds = @($env:IMPERION_M365_TENANT_IDS -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($tenantIds.Count -eq 0) {
        Get-ImperionEntraAppRegistration | Set-ImperionEntraAppRegistrationToBronze
    }
    else {
        foreach ($tenantId in $tenantIds) {
            Get-ImperionEntraAppRegistration -TenantId $tenantId | Set-ImperionEntraAppRegistrationToBronze
        }
    }
}
catch {
    # Schema/permission gate: log loudly and exit; the operator lands the #260 prod apply
    # and the next run converges (idempotent, change-detected upsert).
    Write-ImperionLog -Level Warn -Source 'm365' -Message "Entra app-registrations sync skipped: $($_.Exception.Message)"
}
