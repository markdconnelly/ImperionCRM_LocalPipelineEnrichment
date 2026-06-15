# mileiq/drives - scheduled per-connected-employee MileIQ business-drive pull -> mileiq_drive bronze.
# Cadence: Daily (scheduled-tasks/README.md) - authoritative scheduled mileage capture for expense
# tracking (ADR-0083); the cloud Pipeline handles any on-demand "refresh now". Composes one get +
# one post; keep this short (CLAUDE.md §1). The functions do the heavy lifting so they stay
# reusable by full backfills.
#
# PER-EMPLOYEE OAUTH + DORMANT/DEPLOY-AHEAD (CLAUDE.md §1/§3): MileIQ is per-user read-only OAuth.
# The BACKEND owns the OAuth handshake and custodies each employee's refresh token in Key Vault;
# this repo only reads the short-lived per-employee access token. TRIPLE-GATED - until (a) the
# MileIQ External API credentials are provisioned (markdconnelly/ImperionCRM#495), (b) backend
# MileIQ OAuth custody is live, AND (c) the front-end mileiq_drive bronze migration 0089 lands
# (markdconnelly/ImperionCRM#494 / FE bronze-migration follow-up markdconnelly/ImperionCRM#590),
# the task logs the
# gap and exits cleanly (never crashes the schedule). Personal drives never enter; no comp data
# is read or written. See docs/integrations/mileiq.md.
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion mileiq drives' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\mileiq\drives.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

# Incremental on the drive date; set IMPERION_MILEIQ_SINCE_DAYS=0 for a full authoritative
# backfill (the local pipeline owns the historical window).
$sinceDays = if ($env:IMPERION_MILEIQ_SINCE_DAYS) { [int]$env:IMPERION_MILEIQ_SINCE_DAYS } else { 7 }

try {
    Get-ImperionMileIqDrive -SinceDays $sinceDays | Set-ImperionMileIqDriveToBronze
}
catch {
    # Credential / schema gate: an unreachable per-employee token, a missing employee_profile /
    # mileiq_drive table, or backend custody not yet live must not crash the schedule - log
    # loudly and exit; the operator provisions/applies and the next run converges (idempotent
    # upsert on mileiq_drive_id). Never log a drive's locations, miles, or amounts.
    Write-ImperionLog -Level Warn -Source 'mileiq' -Message "MileIQ drive sync skipped: $($_.Exception.Message)"
}
