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
# estate-sweep helper logs a Warn per tenant and continues so the schedule never crashes.
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

Invoke-ImperionM365EstateSweep -Source 'defender' -Label 'Defender XDR' -PerTenant {
    param($TenantId)
    if ($TenantId) { Get-ImperionDefenderObject -TenantId $TenantId | Set-ImperionDefenderToBronze }
    else { Get-ImperionDefenderObject | Set-ImperionDefenderToBronze }
}
