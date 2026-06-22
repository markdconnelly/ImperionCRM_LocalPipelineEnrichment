function Invoke-ImperionAutotaskTimeEntrySync {
    <#
    .SYNOPSIS
        Bulk-reconcile Autotask TimeEntry records into the autotask_time_entry bronze table (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/autotask/time-entries.task.ps1. Authoritative bulk reconcile for employee time
        tracking (ADR-0082); the cloud Pipeline PL-2 (ImperionCRM_Pipeline#101) handles on-demand
        "refresh now". Incremental on lastModifiedDateTime — -SinceDays controls the window (env
        fallback IMPERION_AUTOTASK_TIME_SINCE_DAYS, default 7; 0 = full authoritative backfill, the
        local pipeline owns the historical window). Idempotent. Requires Initialize-ImperionContext;
        fails closed (the get function logs + exits) until the Autotask API credentials are provisioned.
    .EXAMPLE
        Invoke-ImperionAutotaskTimeEntrySync
    .EXAMPLE
        Invoke-ImperionAutotaskTimeEntrySync -SinceDays 0
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([string] $TenantId, [int] $SinceDays)
    if (-not $PSBoundParameters.ContainsKey('SinceDays')) {
        $SinceDays = if ($env:IMPERION_AUTOTASK_TIME_SINCE_DAYS) { [int] $env:IMPERION_AUTOTASK_TIME_SINCE_DAYS } else { 7 }
    }
    $getArgs = @{ SinceDays = $SinceDays }
    if ($TenantId) { $getArgs.TenantId = $TenantId }
    Get-ImperionAutotaskTimeEntry @getArgs | Set-ImperionAutotaskTimeEntryToBronze
}
