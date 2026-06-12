# m365/defender - hourly Defender XDR incidents + alerts pull -> bronze
# (defender_incidents / defender_alerts, issue #138 / front-end migration 0076 + ADR-0059).
# Cadence: Hourly (scheduled-tasks/README.md) - incidents are operationally timely; the
# change-detected upsert keeps re-runs cheap. Composes one get + one post; keep this short
# (CLAUDE.md §1). Auth is the module's cert-SP Graph token (SecurityIncident.Read.All +
# SecurityAlert.Read.All, already admin-consented); single-tenant against the Imperion
# company tenant by default - set IMPERION_M365_TENANT_IDS for fan-out (per-tenant
# isolation: each row is stamped with its owning tenant).
#
# GATED: until front-end migration 0076 is applied to prod the post fails loudly; the
# catch below logs a Warn and exits cleanly so the schedule never crashes.
# NOTE: the defender_incident_ticket_link table (ADR-0059) is NOT written here - the
# incident<->Autotask pairing belongs to the linking flows, not the collector.
#
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion m365 defender' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\m365\defender.task.ps1"' `
#     -Interval Hourly

Import-Module ImperionPipeline
Initialize-ImperionContext

try {
    $tenantIds = @($env:IMPERION_M365_TENANT_IDS -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($tenantIds.Count -eq 0) {
        Get-ImperionDefenderObject | Set-ImperionDefenderToBronze
    }
    else {
        foreach ($tenantId in $tenantIds) {
            Get-ImperionDefenderObject -TenantId $tenantId | Set-ImperionDefenderToBronze
        }
    }
}
catch {
    # Schema/permission gate: log loudly and exit; the operator lands the 0076 prod apply
    # and the next run converges (idempotent, change-detected upsert).
    Write-ImperionLog -Level Warn -Source 'defender' -Message "Defender XDR sync skipped: $($_.Exception.Message)"
}
