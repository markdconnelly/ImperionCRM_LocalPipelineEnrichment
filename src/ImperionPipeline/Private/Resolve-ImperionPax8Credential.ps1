function Resolve-ImperionPax8Credential {
    <#
    .SYNOPSIS
        Resolve the Pax8 OAuth2 client-credentials pair (client id + client secret): explicit
        values, else SecretStore mirror, else Key Vault original.
    .DESCRIPTION
        Thin two-part vendor adapter over Resolve-ImperionVendorSecret (issue #279, epic #1042;
        the KQM/Datto pattern, ADR-0009). Pax8 is an MSP-WIDE COMPANY credential — Imperion's
        own single distributor-account app, not a per-client key — exchanged for a short-lived
        bearer by the connect helper Invoke-ImperionPax8Request (which owns the OAuth2
        client-credentials exchange and redacts the secret from logs). Each half resolves through
        the same three-tier order (explicit value, else SecretStore mirror, else Key Vault via
        the cert SP). GATED: throws until both are provisioned (Mark-gated), so the scheduled
        task logs the gap and exits cleanly (idempotent re-run converges). Titles, defaults, and
        the thrown messages live in Get-ImperionVendorSecretCatalog ('pax8clientid'/'pax8secret').
        Returns @{ ClientId; ClientSecret }; the secret is never logged.
    .PARAMETER ClientId
        Explicit client id override; defaults to the SecretStore/Key Vault resolution.
    .PARAMETER ClientSecret
        Explicit client secret override; defaults to the SecretStore/Key Vault resolution.
    .EXAMPLE
        $cred = Resolve-ImperionPax8Credential
        Invoke-ImperionPax8Request @cred -Path '/v1/companies'
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string] $ClientId,
        [string] $ClientSecret
    )
    return @{
        ClientId     = Resolve-ImperionVendorSecret -Vendor 'pax8clientid' -Value $ClientId
        ClientSecret = Resolve-ImperionVendorSecret -Vendor 'pax8secret' -Value $ClientSecret
    }
}
