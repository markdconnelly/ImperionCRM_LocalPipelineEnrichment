function Get-ImperionDarkWebIdCompromise {
    <#
    .SYNOPSIS
        Collect Dark Web ID compromised-credential records and flatten them to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6): pages the Dark Web ID compromises endpoint via the
        connect layer and flattens each to the standard flat-table envelope. Target: bronze
        darkwebid_exposures (front-end migration 0043) → silver credential_exposure. Returns rows;
        does not write. Requires Initialize-ImperionContext.

        AUTH: Dark Web ID uses HTTP Basic auth (username + password) — a COMPANY credential in the
        system (the `{username, password}` blob in Key Vault conn-company-darkwebid, ADR-0040), not
        a local SecretStore secret — so both halves are passed in by the caller/task.
        CONFIRM BEFORE LIVE USE: path and field names (email/breachSource/dateFound/exposedData/
        passwordType/…) are ASSUMPTIONS shared with the cloud Pipeline (ADR-0040).
    .PARAMETER Username
        Dark Web ID account username (company credential), the user half of the Basic auth pair.
    .PARAMETER Password
        Dark Web ID account password (company credential), the password half of the Basic auth pair.
    .PARAMETER Domain
        Optional client domain to scope the query.
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant.
    .PARAMETER BaseUri
        Dark Web ID API base. Default 'https://secure.darkwebid.com'.
    .EXAMPLE
        Get-ImperionDarkWebIdCompromise -Username $user -Password $pass -Domain 'acme.com'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    # Dark Web ID uses HTTP Basic auth (username+password, Kaseya docs); the pair is resolved from
    # Key Vault upstream and threaded through to the connect layer as wire strings — same string
    # posture as every other connector's ApiKey/AccessToken param (CLAUDE.md §4).
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingUsernameAndPasswordParams', '')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'Password')]
    param(
        [Parameter(Mandatory)][string] $Username,
        [Parameter(Mandatory)][string] $Password,
        [string] $Domain,
        [string] $TenantId,
        [string] $BaseUri = 'https://secure.darkwebid.com'
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }

    $path = if ($Domain) { '/compromises?domain={0}&page[size]=100' -f [uri]::EscapeDataString($Domain) } else { '/compromises?page[size]=100' }
    $records = Invoke-ImperionDarkWebIdRequest -Username $Username -Password $Password -Uri ('{0}{1}' -f $BaseUri.TrimEnd('/'), $path)

    $map = [ordered]@{
        email         = 'email'
        domain        = 'domain'
        breach_source = 'breachSource'
        breach_date   = 'dateFound'
        password_type = 'passwordType'
        exposed_data  = { param($c) (Get-ImperionMember $c 'exposedData') | Join-ImperionValues }
        severity      = 'severity'
        status        = 'status'
    }

    $records | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'darkwebid' -TenantId $TenantId -ExternalIdProperty 'id'
}
