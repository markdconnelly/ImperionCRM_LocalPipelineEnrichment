function Resolve-ImperionEasyDmarcApiKey {
    <#
    .SYNOPSIS
        Resolve the EasyDMARC API key: explicit value, else SecretStore mirror, else Key Vault original.
    .DESCRIPTION
        Thin vendor adapter over Resolve-ImperionVendorSecret with the 'easydmarc' catalog entry
        (issue #228; the KQM/Voyage pattern, ADR-0009). EasyDMARC is a COMPANY credential —
        Imperion's own MSP account, not a per-client key. The value is returned to the caller and
        never logged; EasyDMARC sends it as an `Authorization: Bearer` header (NOT the
        querystring). GATED: throws until the key is provisioned (Mark-gated, plan must include
        API access), so the scheduled task logs the gap and exits cleanly. Titles, defaults, and
        the thrown message live in Get-ImperionVendorSecretCatalog.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $ApiKey)
    return Resolve-ImperionVendorSecret -Vendor 'easydmarc' -Value $ApiKey
}
