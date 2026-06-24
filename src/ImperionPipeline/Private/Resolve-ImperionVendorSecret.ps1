function Resolve-ImperionVendorSecret {
    <#
    .SYNOPSIS
        Resolve a company vendor API key/token: explicit value, else the Key Vault value the
        database `connection` registry points at (registry-backed vendors) or a named Key Vault
        secret (LP-only vendors), else throw.
    .DESCRIPTION
        The one deep resolver behind every per-vendor adapter (epic #318, supersedes the
        #228/ADR-0009 three-tier shape). The local SecretStore is NO LONGER consulted for vendor
        secrets — the database is the authoritative link and Key Vault is the single store, so
        the backend, the cloud Pipeline, and this repo all read the SAME secret.

        The -Vendor key selects a row in Get-ImperionVendorSecretCatalog. Resolution order:

          1. An explicit -Value wins (no DB / no vault is touched).
          2. REGISTRY-BACKED entry (has Provider/Field): Resolve-ImperionCompanyCredential reads
             the scope='company' connection row, follows keyvault_secret_ref to Key Vault, and
             extracts the blob field — the DB-authoritative path.
          3. KV-BY-NAME entry (has VaultSecret): read that Key Vault secret directly via the cert
             SP, extracting the optional BlobField. For LP-only vendors with no registry row.
          4. Else throw the catalog's message — UNLESS it is $null (e.g. KQM is caller-gated
             upstream and returns $null without throwing).

        The value is returned to the caller and never logged; redaction at the transport seam
        (Invoke-ImperionRestWithRetry) is the second guard.
    .PARAMETER Vendor
        The catalog key (e.g. 'cdw', 'meta', 'kqm', 'itglue').
    .PARAMETER Value
        An explicit, caller-supplied key/token that short-circuits resolution.
    .PARAMETER Connection
        An open Npgsql connection reused for the registry lookup. Optional — registry-backed
        resolution opens (and disposes) its own when omitted.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string] $Vendor,
        [string] $Value,
        $Connection
    )

    if ($Value) { return $Value }

    $spec = (Get-ImperionVendorSecretCatalog)[$Vendor]
    if (-not $spec) {
        throw "Unknown vendor secret '$Vendor': no entry in Get-ImperionVendorSecretCatalog."
    }

    # .Contains is the StrictMode-safe optional-key probe for a hashtable (member access would
    # throw on an absent key). A registry-backed entry carries Provider; a KV-by-name entry
    # carries VaultSecret.
    if ($spec.Contains('Provider')) {
        $Value = Resolve-ImperionCompanyCredential -Provider $spec.Provider -Field $spec.Field -Connection $Connection
    }
    else {
        $Value = Get-ImperionKeyVaultSecret -Name $spec.VaultSecret
        $blobField = $spec['BlobField']
        if ($Value -and $blobField) {
            $Value = ConvertFrom-ImperionCredentialBlob -Value $Value -Field $blobField
        }
    }

    if (-not $Value -and $spec.ErrorMessage) {
        throw $spec.ErrorMessage
    }
    return $Value
}
