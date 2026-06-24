function Resolve-ImperionCompanyCredential {
    <#
    .SYNOPSIS
        Resolve a COMPANY/MSP-wide vendor credential from the `connection` registry into the
        Key Vault value the collectors consume — the company-scope mirror of
        Resolve-ImperionTenantCredential.
    .DESCRIPTION
        The keystone of DB-AUTHORITATIVE company credential resolution (issue #319, epic #318).
        The database `connection` registry is the single authoritative link the backend, the
        cloud Pipeline, and this repo all share: the GUI writes the secret to Key Vault under a
        standardized name and records that name on the registry row; every plane then reads the
        SAME Key Vault secret by following the row. This resolver makes the on-prem plane read
        the row rather than a hard-coded vault name or a local SecretStore mirror, so all three
        planes stay on one credential with zero drift.

        Resolution:
          1. SELECT the newest active scope='company' connection row for the provider and take
             its keyvault_secret_ref (the standardized conn-company-<provider> name).
          2. Get-ImperionKeyVaultSecret reads that secret via the cert-backed app SP (the app
             holds Key Vault Secrets User; CLAUDE.md §2). This is the ONLY credential the local
             SecretStore is consulted for — every vendor secret now lives in Key Vault.
          3. ConvertFrom-ImperionCredentialBlob extracts the requested field from the JSON
             credential blob the backend writes (setSecret(name, JSON.stringify(fields)), #299);
             a legacy bare-string secret passes through unchanged.
          4. No row / no secret (provider not connected) -> $null, OR throw when -FailClosed.

        The provider name is the DB connection_provider enum VALUE (e.g. 'televy', not the LP
        internal 'telivy'; 'quotemanager' for KQM). Secret material is returned only to the
        immediate caller and never logged.
    .PARAMETER Provider
        The connection_provider enum value, e.g. 'itglue' | 'televy' | 'quotemanager' | 'pax8'.
    .PARAMETER Field
        The JSON field to extract from the credential blob, e.g. 'apiKey' | 'clientSecret'.
    .PARAMETER Connection
        An open Npgsql connection (Open-ImperionDbConnection). Optional — when omitted this
        opens (and disposes) its own short-lived connection via New-ImperionDbConnection, so a
        thin caller need not manage one.
    .PARAMETER FailClosed
        Throw instead of returning $null when no usable credential is found.
    .EXAMPLE
        $key = Resolve-ImperionCompanyCredential -Provider 'itglue' -Field 'apiKey'
    .EXAMPLE
        $secret = Resolve-ImperionCompanyCredential -Provider 'pax8' -Field 'clientSecret' -FailClosed
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string] $Provider,
        [Parameter(Mandatory)][string] $Field,
        $Connection,
        [switch] $FailClosed
    )

    $where = "for company provider '$Provider' (field '$Field')"

    $ownConnection = -not $Connection
    if ($ownConnection) { $Connection = New-ImperionDbConnection }
    try {
        $sql = @'
SELECT keyvault_secret_ref
FROM connection
WHERE scope = 'company' AND provider = @provider AND status = 'active'
  AND keyvault_secret_ref IS NOT NULL
ORDER BY connected_at DESC
LIMIT 1
'@
        $row = Invoke-ImperionDbQuery -Connection $Connection -Sql $sql -Parameters @{ provider = $Provider } |
            Select-Object -First 1

        if (-not $row -or -not $row.keyvault_secret_ref) {
            if ($FailClosed) { throw "No active company connection $where." }
            return $null
        }

        $secret = Get-ImperionKeyVaultSecret -Name $row.keyvault_secret_ref
        if (-not $secret) {
            if ($FailClosed) { throw "Key Vault secret '$($row.keyvault_secret_ref)' resolved empty $where." }
            return $null
        }

        return (ConvertFrom-ImperionCredentialBlob -Value $secret -Field $Field)
    }
    finally {
        if ($ownConnection -and $Connection) { $Connection.Dispose() }
    }
}
