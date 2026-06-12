# plaud/recordings - daily Plaud recording pull -> bronze (plaud_recordings).
# Cadence: Daily (scheduled-tasks/README.md). Composes one get + one post; keep this short
# (CLAUDE.md §1). Plaud is an MCP server with a per-user OAuth token (issue #72): Mark
# grants it once in a browser; the SecretStore secret plaud-oauth-token holds it.
#
# DOUBLE-GATED until operator steps land (logs + exits cleanly, never crashes the schedule):
#   1. the plaud-oauth-token secret must exist AND be fresh - refresh can break and need a
#      human re-login (the issue's FAIL-LOUDLY rule: log + skip, never crash the task);
#   2. the plaud_recordings bronze table needs the front-end migration (schema handoff,
#      docs/integrations/plaud.md) - the upsert fails loudly until it lands.
#
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion plaud recordings' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\plaud\recordings.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

try {
    Get-ImperionPlaudRecording | Set-ImperionPlaudRecordingToBronze
}
catch {
    # Auth or schema gate: log loudly and exit; the operator re-logs-in / lands the
    # migration and the next run converges (idempotent, change-detected upsert).
    Write-ImperionLog -Level Warn -Source 'plaud' -Message "Plaud recording sync skipped (re-auth or pending migration?): $($_.Exception.Message)"
}
