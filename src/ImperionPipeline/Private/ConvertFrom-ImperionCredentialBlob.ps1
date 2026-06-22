function ConvertFrom-ImperionCredentialBlob {
    <#
    .SYNOPSIS
        Extract a named field from a JSON credential blob, else return the value unchanged.
    .DESCRIPTION
        The credential registry stores each conn-company-<provider> secret as a JSON blob of
        the provider's form fields — backend credentials.ts does
        setSecret(name, JSON.stringify(fields)), e.g. {"apiKey":"…","region":"us"} — whose
        own comment says "the ingestion engines parse what they need". The vendor collectors
        need exactly one field (the API key), so this extracts blob.<Field>.

        A value that is NOT a JSON object (a legacy bare-string secret, or anything that does
        not parse) passes through unchanged, so Resolve-ImperionVendorSecret is safe to call
        this for every BlobField vendor without breaking the bare-string vendors. When the
        value IS a JSON object but the field is missing/empty (a real misconfiguration), it
        throws a clear, actionable error rather than handing the vendor API a bad key (#299).

        The value is returned to the caller and never logged.
    .PARAMETER Value
        The raw Key Vault secret value.
    .PARAMETER Field
        The JSON field to extract (e.g. 'apiKey').
    .EXAMPLE
        ConvertFrom-ImperionCredentialBlob -Value '{"apiKey":"abc","region":"us"}' -Field apiKey  # -> 'abc'
    .EXAMPLE
        ConvertFrom-ImperionCredentialBlob -Value 'rawkey' -Field apiKey  # -> 'rawkey' (unchanged)
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string] $Value,
        [Parameter(Mandatory)][string] $Field
    )

    # Not a JSON object literal -> a bare-string secret; return it untouched.
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value.TrimStart()[0] -ne '{') {
        return $Value
    }

    try {
        $blob = $Value | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return $Value  # looked like JSON but is not — treat as a bare string
    }

    $hasField = ($blob.PSObject.Properties.Name -contains $Field)
    if (-not $hasField -or [string]::IsNullOrEmpty([string] $blob.$Field)) {
        throw "Credential blob is missing the '$Field' field. Re-save the credential in " +
            'Settings -> Credentials so the Key Vault secret carries it (issue #299).'
    }

    return [string] $blob.$Field
}
