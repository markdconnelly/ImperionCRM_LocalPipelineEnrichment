function Resolve-ImperionTenantCredential {
    <#
    .SYNOPSIS
        Resolve a managed client tenant's per-tenant credential from the `connection`
        registry into a splat the token primitives / vendor requests consume directly.
    .DESCRIPTION
        The keystone of multi-tenant credential RESOLUTION (issue #257, epic #255,
        ADR-0028) — the deep adapter that mirrors Resolve-ImperionVendorSecret for the
        per-client-app world. The pipeline polls many client tenants, each with the
        CLIENT's OWN credential; this reads the GUI-mapped `connection` row (ADR-0103
        credential registry: scope=client, linked to the customer `account`) and returns
        the credential material the caller splats into Get-ImperionAccessToken /
        Get-ImperionGraphToken / Get-ImperionArmToken (ClientId + cert/secret) or the
        UniFi request (ApiKey).

        Resolution:
          1. SELECT the newest active scope='client' row for (account_id, provider).
          2. Branch on `auth_method`:
             - 'certificate' -> @{ ClientId; CertThumbprint }              (+ TenantId)
             - 'secret'      -> @{ ClientId; ClientSecret=<securestring> }  (+ TenantId)
                               (the secret VALUE is read from Key Vault by its NAME on the
                                row's keyvault_secret_ref, converted to a SecureString so
                                the token prims — which take -ClientSecret [securestring] —
                                consume the splat directly; the value is never logged.)
             - 'api_key'     -> @{ ApiKey=<string> }                       (UniFi)
          3. No row / missing material (no consent yet) -> $null, OR throw when -FailClosed.

        Secret material is NEVER logged or returned except inside the splat the caller
        immediately consumes; redaction at the transport seam is the second guard. No
        secret value is ever passed on a command line or persisted here (CLAUDE.md §9).

        NOTE (auth_method='api_key'): the front-end `connection.auth_method` CHECK today
        allows only ('certificate','secret') — the 'api_key' arm is forward-looking and
        stays dormant until a FE migration widens the CHECK and the UniFi custody surface
        (backend #229) writes such rows. It is implemented now so the resolver is ready.

        NOTE (-TenantId): the `connection` table has no tenant_id column (tenant->account
        is modelled by account_tenant); selection is by (account_id, provider). -TenantId
        is carried into the returned splat (so the result is directly splattable into the
        token prims, which require -TenantId) and used in messages. Disambiguating MULTIPLE
        client tenants under ONE account is a follow-up (the registry currently maps one
        live tenant).
    .PARAMETER Connection
        An open Npgsql connection (from Open-ImperionDbConnection), as Invoke-ImperionDbQuery.
    .PARAMETER AccountId
        The owning customer `account` id (uuid) the credential serves.
    .PARAMETER Provider
        The connection provider, e.g. 'm365' | 'azure' | 'unifi'.
    .PARAMETER TenantId
        The client's Entra tenant id (uuid). Carried into the cert/secret splat for the
        token prims; not a row selector today (see NOTE above).
    .PARAMETER FailClosed
        Throw instead of returning $null when no usable credential is found.
    .EXAMPLE
        $cred = Resolve-ImperionTenantCredential -Connection $c -AccountId $a -Provider 'm365' -TenantId $t
        if ($cred) { $tok = Get-ImperionAccessToken @cred -Resource 'https://graph.microsoft.com/.default' }
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'Bridges a Key Vault plaintext secret into the SecureString that Get-ImperionAccessToken -ClientSecret requires. The value is read by reference, converted in-place into the returned splat, and never logged, written to disk, or passed on a command line (CLAUDE.md §9).')]
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)] $Connection,
        [Parameter(Mandatory)][string] $AccountId,
        [Parameter(Mandatory)][string] $Provider,
        [string] $TenantId,
        [switch] $FailClosed
    )

    $where = "for account '$AccountId' provider '$Provider'"

    $sql = @'
SELECT client_id, auth_method, keyvault_secret_ref, cert_thumbprint
FROM connection
WHERE scope = 'client' AND account_id = @account AND provider = @provider
  AND status = 'active'
ORDER BY connected_at DESC
LIMIT 1
'@
    $row = Invoke-ImperionDbQuery -Connection $Connection -Sql $sql -Parameters @{
        account = $AccountId; provider = $Provider
    } | Select-Object -First 1

    if (-not $row) {
        if ($FailClosed) { throw "No active client connection $where." }
        return $null
    }

    # Common splat fragment for the token prims: ClientId + (when known) TenantId.
    $base = @{ ClientId = $row.client_id }
    if ($TenantId) { $base.TenantId = $TenantId }

    switch ($row.auth_method) {
        'certificate' {
            if (-not $row.cert_thumbprint) {
                if ($FailClosed) { throw "Certificate auth but no cert_thumbprint $where." }
                return $null
            }
            return ($base + @{ CertThumbprint = $row.cert_thumbprint })
        }
        'secret' {
            if (-not $row.keyvault_secret_ref) {
                if ($FailClosed) { throw "Secret auth but no keyvault_secret_ref $where." }
                return $null
            }
            $secret = Get-ImperionKeyVaultSecret -Name $row.keyvault_secret_ref
            if (-not $secret) {
                if ($FailClosed) { throw "Key Vault secret '$($row.keyvault_secret_ref)' resolved empty $where." }
                return $null
            }
            return ($base + @{ ClientSecret = (ConvertTo-SecureString $secret -AsPlainText -Force) })
        }
        'api_key' {
            if (-not $row.keyvault_secret_ref) {
                if ($FailClosed) { throw "API-key auth but no keyvault_secret_ref $where." }
                return $null
            }
            $key = Get-ImperionKeyVaultSecret -Name $row.keyvault_secret_ref
            if (-not $key) {
                if ($FailClosed) { throw "Key Vault secret '$($row.keyvault_secret_ref)' resolved empty $where." }
                return $null
            }
            return @{ ApiKey = $key }
        }
        default {
            if ($FailClosed) { throw "Unsupported auth_method '$($row.auth_method)' $where." }
            return $null
        }
    }
}
