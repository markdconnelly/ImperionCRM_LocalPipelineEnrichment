function Resolve-ImperionITGlueApiKey {
    <#
    .SYNOPSIS
        Resolve the IT Glue API key from Key Vault (the standardized credential-registry name).
    .DESCRIPTION
        Thin vendor adapter over Resolve-ImperionVendorSecret with the 'itglue' catalog entry
        (issue #291). Reads the standardized credential-registry secret conn-company-itglue from
        Key Vault via the cert SP — the same secret the cloud reads — so on-prem IT Glue
        collection leverages Key Vault the same way the cloud does (no SecretStore mirror). Throws
        the catalog message when unresolved. The value is returned to the caller and never logged.
    .PARAMETER ApiKey
        An explicit key that short-circuits resolution (e.g. tests).
    .EXAMPLE
        $apiKey = Resolve-ImperionITGlueApiKey
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $ApiKey)
    return Resolve-ImperionVendorSecret -Vendor 'itglue' -Value $ApiKey
}
