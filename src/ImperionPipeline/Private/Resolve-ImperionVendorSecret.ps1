function Resolve-ImperionVendorSecret {
    <#
    .SYNOPSIS
        Resolve a vendor API key/token through the shared three-tier order:
        explicit value, else SecretStore mirror, else Key Vault original, else throw.
    .DESCRIPTION
        The one deep resolver behind every per-vendor adapter (issue #228, the KQM/Voyage
        pattern, ADR-0009). The -Vendor key selects a row in Get-ImperionVendorSecretCatalog
        which supplies the SecretStore title, the Key Vault title (config-overridable), and the
        verbatim error message. Resolution order, exactly as the per-vendor resolvers always ran:

          1. An explicit -Value wins (no vault is touched).
          2. Else, when the SecretStore vault is unlocked this run AND the secret-names config
             names the mirror, read it from the SecretStore.
          3. Else read the Key Vault original (the config override title, else the catalog
             default), via the cert SP.
          4. Else throw the catalog's message — UNLESS it is $null (KQM is caller-gated upstream
             and returns $null without throwing).

        The value is returned to the caller and never logged; redaction at the transport seam
        (Invoke-ImperionRestWithRetry) is the second guard. No secret VALUE is ever passed on a
        command line or persisted here.
    .PARAMETER Vendor
        The catalog key (e.g. 'cdw', 'meta', 'kqm').
    .PARAMETER Value
        An explicit, caller-supplied key/token that short-circuits resolution.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string] $Vendor,
        [string] $Value
    )

    if ($Value) { return $Value }

    $spec = (Get-ImperionVendorSecretCatalog)[$Vendor]
    if (-not $spec) {
        throw "Unknown vendor secret '$Vendor': no entry in Get-ImperionVendorSecretCatalog."
    }

    $secretNames = Get-ImperionSecretNames
    if ($script:ImperionSecretStoreVault -and
        $secretNames -is [System.Collections.IDictionary] -and $secretNames.Contains($spec.SecretStoreKey)) {
        $Value = Get-ImperionSecretValue -Name $secretNames[$spec.SecretStoreKey]
    }
    if (-not $Value) {
        $keyVaultSecretName =
            if ($secretNames -is [System.Collections.IDictionary] -and $secretNames.Contains($spec.VaultSecretConfigKey)) {
                $secretNames[$spec.VaultSecretConfigKey]
            }
            else { $spec.VaultDefault }
        $Value = Get-ImperionKeyVaultSecret -Name $keyVaultSecretName
    }
    if (-not $Value -and $spec.ErrorMessage) {
        throw $spec.ErrorMessage
    }
    return $Value
}
