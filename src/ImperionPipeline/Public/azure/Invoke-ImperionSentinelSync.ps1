function Invoke-ImperionSentinelSync {
    <#
    .SYNOPSIS
        Collect Microsoft Sentinel objects into the sentinel_* bronze tables (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/azure/sentinel.task.ps1. Auth is the cert SP's existing Azure RBAC Reader (no
        new grant, issue #97); workspaces without Sentinel are logged + skipped inside the get.
        Idempotent change-detected upsert. Requires Initialize-ImperionContext.
    .EXAMPLE
        Invoke-ImperionSentinelSync
    #>
    [CmdletBinding()]
    param()

    Get-ImperionSentinelObject | Set-ImperionSentinelToBronze
}
