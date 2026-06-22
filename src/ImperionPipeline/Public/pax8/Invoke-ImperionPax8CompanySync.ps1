function Invoke-ImperionPax8CompanySync {
    <#
    .SYNOPSIS
        Pull Pax8 customer companies into the pax8_companies bronze table (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) for Pax8
        (issue #279, epic #1042). Credential: the MSP-wide OAuth2 client-credentials pair resolved
        SecretStore-first / Key Vault-fallback (Resolve-ImperionPax8Credential); the bearer
        exchange is owned by the connect helper. Idempotent upsert. Requires
        Initialize-ImperionContext; fails closed — an unprovisioned credential or a missing
        pax8_companies table is logged (warn) and skipped, never crashing the schedule.
    .EXAMPLE
        Invoke-ImperionPax8CompanySync
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    try {
        Get-ImperionPax8Company | Set-ImperionPax8CompanyToBronze
    }
    catch {
        Write-ImperionLog -Level Warn -Source 'pax8' -Message "Pax8 company sync skipped: $($_.Exception.Message)"
    }
}
