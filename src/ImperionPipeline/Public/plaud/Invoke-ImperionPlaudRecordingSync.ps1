function Invoke-ImperionPlaudRecordingSync {
    <#
    .SYNOPSIS
        Pull Plaud recordings into the plaud_recordings bronze table (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/plaud/recordings.task.ps1. Plaud is an MCP server with a per-user OAuth token
        (issue #72): Mark grants it once in a browser; the SecretStore secret plaud-oauth-token holds it.
        Idempotent, change-detected upsert. Requires Initialize-ImperionContext; DOUBLE-GATED — a missing
        / stale plaud-oauth-token (re-auth) or a pending plaud_recordings front-end migration is logged
        (warn) and skipped, never crashing the schedule.
    .EXAMPLE
        Invoke-ImperionPlaudRecordingSync
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    try {
        Get-ImperionPlaudRecording | Set-ImperionPlaudRecordingToBronze
    }
    catch {
        # Auth or schema gate: log loudly and exit; the operator re-logs-in / lands the
        # migration and the next run converges (idempotent, change-detected upsert).
        Write-ImperionLog -Level Warn -Source 'plaud' -Message "Plaud recording sync skipped (re-auth or pending migration?): $($_.Exception.Message)"
    }
}
