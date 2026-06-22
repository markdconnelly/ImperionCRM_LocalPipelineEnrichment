function Invoke-ImperionDattoBcdrBackupSync {
    <#
    .SYNOPSIS
        Pull Datto BCDR backup posture into the datto_bcdr_backups bronze table (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/dattobcdr/backups.task.ps1. Per-device backup posture (protected / last-good
        backup). Credential: SecretStore 'datto-bcdr-api-key' mirror, else Key Vault 'Datto-BCDR-API-Key'
        via the cert SP (an MSP-WIDE vendor credential, ADR-0018); auth is an Authorization: Bearer
        header. Idempotent upsert. Requires Initialize-ImperionContext; fails closed — an unreachable
        key or a missing datto_bcdr_backups table is logged (warn) and skipped, never crashing the
        schedule (issue #195).
    .EXAMPLE
        Invoke-ImperionDattoBcdrBackupSync
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    try {
        Get-ImperionDattoBcdrBackup | Set-ImperionDattoBcdrBackupToBronze
    }
    catch {
        # Credential / schema gate: an unreachable datto-bcdr-api-key / Datto-BCDR-API-Key, or a missing
        # datto_bcdr_backups table, must not crash the schedule - log loudly and exit; the next run
        # converges (idempotent upsert).
        Write-ImperionLog -Level Warn -Source 'datto_bcdr' -Message "Datto BCDR backup sync skipped: $($_.Exception.Message)"
    }
}
