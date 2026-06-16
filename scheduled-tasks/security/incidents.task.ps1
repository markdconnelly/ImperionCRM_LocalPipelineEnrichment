# security/incidents - hourly Microsoft security incident + alert + evidence pull -> bronze
# (m365_incidents / m365_alerts / m365_evidence, issue #196 / front-end migration 0119 + ADR-0019).
# Cadence: Hourly (scheduled-tasks/README.md) - incidents are operationally timely; the
# change-detected upsert keeps re-runs cheap. One get covers all three entities (incident ->
# alerts -> evidence, the entity-discriminator pattern); the post routes each to its 0119 table.
# Keep this short (CLAUDE.md §1).
#
# AUTH: read-only Graph via the per-client onboarding app (CLAUDE.md §3, pipeline ADR-0018) -
# Get-ImperionGraphToken cert-SP app-only token (SecurityIncident.Read.All + SecurityAlert.Read.All,
# read-only, already admin-consented). Single-tenant against the Imperion company tenant by default;
# set IMPERION_M365_TENANT_IDS for fan-out (per-tenant isolation: each row stamped with its tenant).
#
# DORMANT until creds provisioned (issue #102 server bringup) + CONFIRM-BEFORE-LIVE on the
# autotask_ticket_ref format (ADR-0019 OPEN ITEM): the collector stores the raw tag candidate
# untouched; the candidate path must be verified against live m365_incidents rows + the Autotask
# ticket shape before the silver MS<->Autotask stitch is wired. See docs/integrations/security-incidents.md.
#
# GATED: front-end migration 0119 (m365_*) is SHIPPED + prod-applied, so the SCHEMA gate is clear.
# Remaining gate is onboarding-app consent for the target tenant; until then the post fails loudly
# and the catch below logs a Warn and exits cleanly so the schedule never crashes.
#
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion-Security-Incidents' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\security\incidents.task.ps1"' `
#     -Interval Hourly

Import-Module ImperionPipeline
Initialize-ImperionContext

try {
    $tenantIds = @($env:IMPERION_M365_TENANT_IDS -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($tenantIds.Count -eq 0) {
        Get-ImperionSecurityIncident | Set-ImperionSecurityIncidentToBronze
    }
    else {
        foreach ($tenantId in $tenantIds) {
            Get-ImperionSecurityIncident -TenantId $tenantId | Set-ImperionSecurityIncidentToBronze
        }
    }
}
catch {
    # Schema/consent gate: log loudly and exit; the operator lands onboarding-app consent and the
    # next run converges (idempotent, change-detected upsert).
    Write-ImperionLog -Level Warn -Source 'm365' -Message "Security incident sync skipped: $($_.Exception.Message)"
}
