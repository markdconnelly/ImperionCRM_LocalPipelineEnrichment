function Resolve-ImperionKqmApiKey {
    <#
    .SYNOPSIS
        Resolve the KQM API key: explicit value, else SecretStore mirror, else Key Vault original.
    .DESCRIPTION
        Thin vendor adapter over Resolve-ImperionVendorSecret with the 'kqm' catalog entry
        (issue #228; the Voyage pattern, ADR-0009). The value is returned to the caller and never
        logged; KQM URLs carry it as ?apikey=, so the querystring redaction in
        Invoke-ImperionRestWithRetry is the second guard. NOTE: unlike the other vendors this
        resolver returns $null (does NOT throw) when unresolved — KQM is caller-gated upstream
        (catalog ErrorMessage = $null). Titles and defaults live in
        Get-ImperionVendorSecretCatalog.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $ApiKey)
    return Resolve-ImperionVendorSecret -Vendor 'kqm' -Value $ApiKey
}
