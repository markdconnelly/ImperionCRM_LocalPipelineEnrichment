function Invoke-ImperionSecurityIncidentSync {
    <#
    .SYNOPSIS
        Collect Microsoft security incidents + alerts + evidence into the m365_* bronze tables.
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/security/incidents.task.ps1. One get covers all three entities (incident ->
        alerts -> evidence); the post routes each to its migration-0119 table (issue #196, ADR-0019).
        Read-only Graph via the per-client onboarding app. Per-client security posture (ADR-0126):
        fans out over EVERY mapped client tenant via Invoke-ImperionM365EstateSweep — the same
        registry-driven (account_tenant join an active m365 connection), per-tenant fail-isolated
        sweep the directory collectors already use (#358/#266) — instead of the home tenant only.
        A tenant with no consent/credential is skipped (Warn) and never blocks the rest; DORMANT
        until onboarding-app consent (#102). Idempotent (change-detected upsert) — re-runs converge.
        Requires Initialize-ImperionContext.
    .PARAMETER TenantId
        Pins the sweep to one tenant (the tenant-outer driver, #359); omit for the registry-driven
        estate fan-out (#358). Forwarded only when supplied so the default is the full estate.
    .EXAMPLE
        Invoke-ImperionSecurityIncidentSync
    #>
    [CmdletBinding()]
    param([string] $TenantId)

    # -TenantId pins the sweep to one tenant (the tenant-outer driver, #359); no arg => the
    # registry-driven estate fan-out (#358). Forward only when supplied so the default is unchanged.
    $sweep = @{}
    if ($PSBoundParameters.ContainsKey('TenantId')) { $sweep.TenantId = $TenantId }
    Invoke-ImperionM365EstateSweep @sweep -Label 'M365 security incidents' -PerTenant {
        param($TenantId)
        if ($TenantId) { Get-ImperionSecurityIncident -TenantId $TenantId | Set-ImperionSecurityIncidentToBronze }
        else { Get-ImperionSecurityIncident | Set-ImperionSecurityIncidentToBronze }
    }
}
