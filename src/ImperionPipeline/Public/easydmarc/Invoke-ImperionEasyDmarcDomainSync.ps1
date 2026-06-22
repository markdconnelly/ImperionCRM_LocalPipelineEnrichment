function Invoke-ImperionEasyDmarcDomainSync {
    <#
    .SYNOPSIS
        Pull EasyDMARC domain/DMARC posture into the easydmarc_domains bronze table (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/easydmarc/domains.task.ps1. Credential: SecretStore 'easydmarc-api-key' mirror,
        else Key Vault 'EasyDMARC-API-Key' via the cert SP (a COMPANY credential — Imperion's MSP
        account); auth is an Authorization: Bearer header. Idempotent upsert. Requires
        Initialize-ImperionContext; fails closed — an unreachable key or a missing easydmarc_domains
        table is logged (warn) and skipped, never crashing the schedule (issue #122).
    .EXAMPLE
        Invoke-ImperionEasyDmarcDomainSync
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    try {
        Get-ImperionEasyDmarcDomain | Set-ImperionEasyDmarcDomainToBronze
    }
    catch {
        # Credential / schema gate: an unreachable easydmarc-api-key / EasyDMARC-API-Key, or a
        # missing easydmarc_domains table, must not crash the schedule - log loudly and exit; the
        # operator provisions/rotates the key (and the front-end applies the migration) and the
        # next run converges (idempotent upsert).
        Write-ImperionLog -Level Warn -Source 'easydmarc' -Message "EasyDMARC domain sync skipped: $($_.Exception.Message)"
    }
}
