function Resolve-ImperionDattoRmmApiKey {
    <#
    .SYNOPSIS
        Resolve the Datto RMM API key: explicit value, else SecretStore mirror, else Key Vault original.
    .DESCRIPTION
        Thin vendor adapter over Resolve-ImperionVendorSecret with the 'dattormm' catalog entry
        (issue #228, ADR-0018; the KQM/Voyage pattern, ADR-0009). Datto RMM is an MSP-WIDE vendor
        credential — Imperion's own account, not a per-client key. The value is returned to the
        caller and never logged. Datto RMM exchanges this API key for a SHORT-LIVED BEARER token
        (its /auth/oauth/token endpoint); the connect helper Invoke-ImperionDattoRmmRequest owns
        that exchange and the retry core redacts tokens from logs. GATED: throws until the key is
        provisioned (Mark-gated), so the scheduled task logs the gap and exits cleanly (idempotent
        re-run converges). Titles, defaults, and the thrown message live in
        Get-ImperionVendorSecretCatalog.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $ApiKey)
    return Resolve-ImperionVendorSecret -Vendor 'dattormm' -Value $ApiKey
}
