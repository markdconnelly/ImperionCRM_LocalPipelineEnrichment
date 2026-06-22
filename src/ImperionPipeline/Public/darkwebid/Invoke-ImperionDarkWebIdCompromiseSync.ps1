function Invoke-ImperionDarkWebIdCompromiseSync {
    <#
    .SYNOPSIS
        Pull Dark Web ID compromises into the darkwebid_exposures bronze table (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/darkwebid/compromises.task.ps1. Dark Web ID is a COMPANY credential in Key Vault
        (conn-company-darkwebid, ADR-0040), read here via the cert SP — not a local SecretStore secret
        (CLAUDE.md §2). Optionally scope to one client domain via the inline IMPERION_DARKWEBID_DOMAIN
        env var (omit for all). Idempotent upsert. Requires Initialize-ImperionContext; fails closed —
        an unreachable Key Vault credential surfaces as a thrown error from the get function.
    .EXAMPLE
        Invoke-ImperionDarkWebIdCompromiseSync
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    # Optionally scope to one client domain via IMPERION_DARKWEBID_DOMAIN (omit for all).
    $apiKey = Get-ImperionKeyVaultSecret -Name 'conn-company-darkwebid'

    if ($env:IMPERION_DARKWEBID_DOMAIN) {
        Get-ImperionDarkWebIdCompromise -ApiKey $apiKey -Domain $env:IMPERION_DARKWEBID_DOMAIN | Set-ImperionDarkWebIdCompromiseToBronze
    }
    else {
        Get-ImperionDarkWebIdCompromise -ApiKey $apiKey | Set-ImperionDarkWebIdCompromiseToBronze
    }
}
