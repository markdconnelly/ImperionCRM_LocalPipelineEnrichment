function Invoke-ImperionDattoRmmDeviceSync {
    <#
    .SYNOPSIS
        Pull Datto RMM managed devices into the datto_rmm_devices bronze table (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/dattormm/devices.task.ps1. Credential: SecretStore 'datto-rmm-api-key' mirror,
        else Key Vault 'Datto-RMM-API-Key' via the cert SP (an MSP-WIDE vendor credential, ADR-0018);
        auth is an API-key -> short-lived BEARER exchange owned by the connect helper. Idempotent
        upsert. Requires Initialize-ImperionContext; fails closed — an unreachable key or a missing
        datto_rmm_devices table is logged (warn) and skipped, never crashing the schedule (issue #195).
    .EXAMPLE
        Invoke-ImperionDattoRmmDeviceSync
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    try {
        Get-ImperionDattoRmmDevice | Set-ImperionDattoRmmDeviceToBronze
    }
    catch {
        # Credential / schema gate: an unreachable datto-rmm-api-key / Datto-RMM-API-Key, or a missing
        # datto_rmm_devices table, must not crash the schedule - log loudly and exit; the operator
        # provisions/rotates the key and the next run converges (idempotent upsert).
        Write-ImperionLog -Level Warn -Source 'datto_rmm' -Message "Datto RMM device sync skipped: $($_.Exception.Message)"
    }
}
