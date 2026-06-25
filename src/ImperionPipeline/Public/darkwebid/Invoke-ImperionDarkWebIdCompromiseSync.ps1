function Invoke-ImperionDarkWebIdCompromiseSync {
    <#
    .SYNOPSIS
        Pull Dark Web ID compromises into the darkwebid_exposures bronze table (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/darkwebid/compromises.task.ps1. Dark Web ID uses HTTP Basic auth and is a
        COMPANY credential in the system: a `{username, password}` blob in Key Vault
        conn-company-darkwebid (front-end ADR-0040), resolved here from the `connection` registry via
        Resolve-ImperionCompanyCredential (ADR-0103 / #319) — the DB row points at the standardized
        secret and ConvertFrom-ImperionCredentialBlob extracts each field — NOT a raw Key Vault read.
        Optionally scope to one client domain via the inline IMPERION_DARKWEBID_DOMAIN env var (omit
        for all). Idempotent upsert. Requires Initialize-ImperionContext; fails closed —
        -FailClosed throws when no usable username/password credential is registered.
    .EXAMPLE
        Invoke-ImperionDarkWebIdCompromiseSync
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    # Basic-auth company credential resolved from the registry (DB row -> KV blob -> field), ADR-0103.
    $username = Resolve-ImperionCompanyCredential -Provider 'darkwebid' -Field 'username' -FailClosed
    $password = Resolve-ImperionCompanyCredential -Provider 'darkwebid' -Field 'password' -FailClosed

    # Optionally scope to one client domain via IMPERION_DARKWEBID_DOMAIN (omit for all).
    if ($env:IMPERION_DARKWEBID_DOMAIN) {
        Get-ImperionDarkWebIdCompromise -Username $username -Password $password -Domain $env:IMPERION_DARKWEBID_DOMAIN | Set-ImperionDarkWebIdCompromiseToBronze
    }
    else {
        Get-ImperionDarkWebIdCompromise -Username $username -Password $password | Set-ImperionDarkWebIdCompromiseToBronze
    }
}
