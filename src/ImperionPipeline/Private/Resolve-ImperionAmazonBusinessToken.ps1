function Resolve-ImperionAmazonBusinessToken {
    <#
    .SYNOPSIS
        Resolve the Amazon Business access token: explicit value, else SecretStore mirror, else Key Vault original.
    .DESCRIPTION
        Thin vendor adapter over Resolve-ImperionVendorSecret with the 'amazonbusiness' catalog
        entry (issue #228; the KQM/Voyage pattern, ADR-0009). Amazon Business is a COMPANY
        credential — Imperion's own purchasing account, not a per-client key. The value is
        returned to the caller and never logged; the connect layer sends it as an
        `Authorization: Bearer` header (NOT the querystring). GATED: throws until the token is
        provisioned (Mark-gated, plan must include API access), so the scheduled task logs the gap
        and exits cleanly. Titles, defaults, and the thrown message live in
        Get-ImperionVendorSecretCatalog.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $Token)
    return Resolve-ImperionVendorSecret -Vendor 'amazonbusiness' -Value $Token
}
