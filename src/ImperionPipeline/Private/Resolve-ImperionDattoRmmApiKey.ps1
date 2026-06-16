function Resolve-ImperionDattoRmmApiKey {
    <#
    .SYNOPSIS
        Resolve the Datto RMM API key: explicit value, else SecretStore mirror, else Key Vault original.
    .DESCRIPTION
        Module-internal key resolution shared by the Datto RMM get layer (issue #195, ADR-0018),
        mirroring Resolve-ImperionKqmApiKey / Resolve-ImperionEasyDmarcApiKey exactly (the
        KQM/Voyage pattern, ADR-0009): an explicit -ApiKey wins; else the SecretStore secret
        named by `DattoRmmApiKey` (default 'datto-rmm-api-key') when the vault is unlocked this
        run; else the Key Vault secret named by `DattoRmmApiKeyVaultSecret` (default
        'Datto-RMM-API-Key', the operator-provisioned original in kv-imperioncrm-prd) read by
        the cert SP. Datto RMM is an MSP-WIDE vendor credential — Imperion's own account, not a
        per-client key.

        The value is returned to the caller and never logged. Datto RMM exchanges this API key
        for a SHORT-LIVED BEARER token (its /auth/oauth/token endpoint); the connect helper
        Invoke-ImperionDattoRmmRequest owns that exchange and the retry core redacts tokens from
        logs. GATED: until the key is provisioned (Mark-gated; plan must include API access),
        this throws and the scheduled task logs the gap and exits cleanly (idempotent re-run
        converges).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $ApiKey)

    if ($ApiKey) { return $ApiKey }
    $secretNames = Get-ImperionSecretNames
    if ($script:ImperionSecretStoreVault -and
        $secretNames -is [System.Collections.IDictionary] -and $secretNames.Contains('DattoRmmApiKey')) {
        $ApiKey = Get-ImperionSecretValue -Name $secretNames['DattoRmmApiKey']
    }
    if (-not $ApiKey) {
        $keyVaultSecretName =
            if ($secretNames -is [System.Collections.IDictionary] -and $secretNames.Contains('DattoRmmApiKeyVaultSecret')) {
                $secretNames['DattoRmmApiKeyVaultSecret']
            }
            else { 'Datto-RMM-API-Key' }
        $ApiKey = Get-ImperionKeyVaultSecret -Name $keyVaultSecretName
    }
    if (-not $ApiKey) {
        throw 'Datto RMM API key unavailable: pass -ApiKey, provision the SecretStore secret named by DattoRmmApiKey, or the Key Vault secret named by DattoRmmApiKeyVaultSecret (issue #195, ADR-0018).'
    }
    return $ApiKey
}
