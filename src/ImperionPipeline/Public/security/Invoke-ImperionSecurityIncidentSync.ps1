function Invoke-ImperionSecurityIncidentSync {
    <#
    .SYNOPSIS
        Collect Microsoft security incidents + alerts + evidence into the m365_* bronze tables.
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/security/incidents.task.ps1. One get covers all three entities (incident ->
        alerts -> evidence); the post routes each to its migration-0119 table (issue #196, ADR-0019).
        Read-only Graph via the per-client onboarding app; single-tenant by default, fans out over
        IMPERION_M365_TENANT_IDS (per-tenant isolation). DORMANT until onboarding-app consent (#102);
        the catch logs a Warn and exits cleanly so the schedule never crashes. Requires
        Initialize-ImperionContext.
    .EXAMPLE
        Invoke-ImperionSecurityIncidentSync
    #>
    [CmdletBinding()]
    param()

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
}
