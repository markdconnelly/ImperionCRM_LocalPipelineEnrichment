function Resolve-ImperionTelivyApiKey {
    <#
    .SYNOPSIS
        Resolve the Telivy API key from Key Vault (the standardized credential-registry name).
    .DESCRIPTION
        Thin vendor adapter over Resolve-ImperionVendorSecret with the 'telivy' catalog entry
        (issue #291). Reads the standardized credential-registry secret conn-company-televy from
        Key Vault via the cert SP — the same secret the cloud reads — so on-prem Telivy collection
        leverages Key Vault the same way the cloud does (no SecretStore mirror). Throws the catalog
        message when unresolved. The value is returned to the caller and never logged. (The
        Postgres source value remains 'televy'; the registry provider is 'televy'.)
    .PARAMETER ApiKey
        An explicit key that short-circuits resolution (e.g. tests).
    .EXAMPLE
        $apiKey = Resolve-ImperionTelivyApiKey
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $ApiKey)
    return Resolve-ImperionVendorSecret -Vendor 'telivy' -Value $ApiKey
}
