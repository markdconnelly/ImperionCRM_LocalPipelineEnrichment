function Resolve-ImperionDattoBcdrApiKey {
    <#
    .SYNOPSIS
        Resolve the Datto BCDR API key: explicit value, else SecretStore mirror, else Key Vault original.
    .DESCRIPTION
        Module-internal key resolution shared by the Datto BCDR get layer (issue #195, ADR-0018),
        mirroring Resolve-ImperionKqmApiKey / Resolve-ImperionEasyDmarcApiKey exactly (the
        KQM/Voyage pattern, ADR-0009): an explicit -ApiKey wins; else the SecretStore secret
        named by `DattoBcdrApiKey` (default 'datto-bcdr-api-key') when the vault is unlocked this
        run; else the Key Vault secret named by `DattoBcdrApiKeyVaultSecret` (default
        'Datto-BCDR-API-Key', the operator-provisioned original in kv-imperioncrm-prd) read by
        the cert SP. Datto BCDR is an MSP-WIDE vendor credential — Imperion's own account, not a
        per-client key.

        The value is returned to the caller and never logged; Datto BCDR sends it as an
        `Authorization: Bearer` header (NOT the querystring), so request URLs are not
        secret-bearing. GATED: until the key is provisioned (Mark-gated; plan must include API
        access), this throws and the scheduled task logs the gap and exits cleanly (idempotent
        re-run converges).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $ApiKey)

    if ($ApiKey) { return $ApiKey }
    $secretNames = Get-ImperionSecretNames
    if ($script:ImperionSecretStoreVault -and
        $secretNames -is [System.Collections.IDictionary] -and $secretNames.Contains('DattoBcdrApiKey')) {
        $ApiKey = Get-ImperionSecretValue -Name $secretNames['DattoBcdrApiKey']
    }
    if (-not $ApiKey) {
        $keyVaultSecretName =
            if ($secretNames -is [System.Collections.IDictionary] -and $secretNames.Contains('DattoBcdrApiKeyVaultSecret')) {
                $secretNames['DattoBcdrApiKeyVaultSecret']
            }
            else { 'Datto-BCDR-API-Key' }
        $ApiKey = Get-ImperionKeyVaultSecret -Name $keyVaultSecretName
    }
    if (-not $ApiKey) {
        throw 'Datto BCDR API key unavailable: pass -ApiKey, provision the SecretStore secret named by DattoBcdrApiKey, or the Key Vault secret named by DattoBcdrApiKeyVaultSecret (issue #195, ADR-0018).'
    }
    return $ApiKey
}
