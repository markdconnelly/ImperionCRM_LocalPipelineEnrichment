function Resolve-ImperionMetaToken {
    <#
    .SYNOPSIS
        Resolve the Meta Business Manager system-user token: explicit value, else SecretStore.
    .DESCRIPTION
        Thin vendor adapter over Resolve-ImperionVendorSecret with the 'meta' catalog entry
        (issue #228, ADR-0013; the KQM/Voyage pattern, ADR-0009). The non-expiring Business
        Manager system-user token: explicit -Token, else the SecretStore mirror, else the Key
        Vault original (operator-provisioned, the interim path until #102 bootstraps the
        SecretStore). The value is returned to the caller and never logged; the connect layer
        carries it as an Authorization: Bearer header (never the querystring) and strips Meta's
        access_token parameter from paging URLs as the second guard. Titles, defaults, and the
        thrown message live in Get-ImperionVendorSecretCatalog.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $Token)
    return Resolve-ImperionVendorSecret -Vendor 'meta' -Value $Token
}
