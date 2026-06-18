function Resolve-ImperionMyItProcessApiKey {
    <#
    .SYNOPSIS
        Resolve the myITprocess API key: explicit value, else SecretStore mirror, else Key Vault original.
    .DESCRIPTION
        Thin vendor adapter over Resolve-ImperionVendorSecret with the 'myitprocess' catalog
        entry (issue #228, ADR-0018; the KQM/Voyage pattern, ADR-0009). myITprocess is an
        MSP-WIDE vendor credential — Imperion's own vCIO account, not a per-client key. The value
        is returned to the caller and never logged; myITprocess sends it as an `api_token` header
        (NOT the querystring). GATED: throws until the key is provisioned (Mark-gated), so the
        scheduled task logs the gap and exits cleanly (idempotent re-run converges). Titles,
        defaults, and the thrown message live in Get-ImperionVendorSecretCatalog.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $ApiKey)
    return Resolve-ImperionVendorSecret -Vendor 'myitprocess' -Value $ApiKey
}
