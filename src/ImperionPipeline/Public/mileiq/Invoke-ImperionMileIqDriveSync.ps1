function Invoke-ImperionMileIqDriveSync {
    <#
    .SYNOPSIS
        Pull per-connected-employee MileIQ business drives into the mileiq_drive bronze table (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/mileiq/drives.task.ps1. Authoritative scheduled mileage capture for expense
        tracking (ADR-0083); the cloud Pipeline handles any on-demand "refresh now". MileIQ is per-user
        read-only OAuth: the backend custodies each employee's refresh token in Key Vault; this repo only
        reads the short-lived per-employee access token. Incremental on the drive date via the inline
        IMPERION_MILEIQ_SINCE_DAYS env window (default 7; 0 = full authoritative backfill). Personal
        drives never enter; no comp data is read or written. Idempotent upsert on mileiq_drive_id.
        Requires Initialize-ImperionContext; TRIPLE-GATED (credentials / backend OAuth custody /
        front-end migration) — gaps are logged (warn) and skipped, never crashing the schedule.
    .EXAMPLE
        Invoke-ImperionMileIqDriveSync
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

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
}
