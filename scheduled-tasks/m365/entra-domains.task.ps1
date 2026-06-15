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
# fails loudly; the catch below logs a Warn and exits cleanly so the schedule never crashes.
#
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion m365 entra-domains' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\m365\entra-domains.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

try {
    $tenantIds = @($env:IMPERION_M365_TENANT_IDS -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($tenantIds.Count -eq 0) {
        Get-ImperionEntraDomain | Set-ImperionEntraDomainToBronze
    }
    else {
        foreach ($tenantId in $tenantIds) {
            Get-ImperionEntraDomain -TenantId $tenantId | Set-ImperionEntraDomainToBronze
        }
    }
}
catch {
    # Schema/permission gate: log loudly and exit; the operator lands the #260 prod apply
    # and the next run converges (idempotent, change-detected upsert).
    Write-ImperionLog -Level Warn -Source 'm365' -Message "Entra domains sync skipped: $($_.Exception.Message)"
}
