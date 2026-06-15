function Resolve-ImperionEasyDmarcApiKey {
    <#
    .SYNOPSIS
        Resolve the EasyDMARC API key: explicit value, else SecretStore mirror, else Key Vault original.
    .DESCRIPTION
        Module-internal key resolution shared by the EasyDMARC get layer (issue #122),
        mirroring Resolve-ImperionKqmApiKey / Resolve-ImperionMetaToken exactly (the
        KQM/Voyage pattern, ADR-0009): an explicit -ApiKey wins; else the SecretStore
        secret named by `EasyDmarcApiKey` (default 'easydmarc-api-key') when the vault is
        unlocked this run; else the Key Vault secret named by `EasyDmarcApiKeyVaultSecret`
        (default 'EasyDMARC-API-Key', the operator-provisioned original in kv-imperioncrm-prd)
        read by the cert SP. EasyDMARC is a COMPANY credential — Imperion's own MSP account,
        not a per-client key.

        The value is returned to the caller and never logged; EasyDMARC sends it as an
        `Authorization: Bearer` header (NOT the querystring), so request URLs are not
        secret-bearing. GATED: until the key is provisioned (Mark-gated, plan must include
        API access), this throws and the scheduled task logs the gap and exits cleanly.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $ApiKey)

    if ($ApiKey) { return $ApiKey }
    $secretNames = Get-ImperionSecretNames
    if ($script:ImperionSecretStoreVault -and
        $secretNames -is [System.Collections.IDictionary] -and $secretNames.Contains('EasyDmarcApiKey')) {
        $ApiKey = Get-ImperionSecretValue -Name $secretNames['EasyDmarcApiKey']
    }
    if (-not $ApiKey) {
        $keyVaultSecretName =
            if ($secretNames -is [System.Collections.IDictionary] -and $secretNames.Contains('EasyDmarcApiKeyVaultSecret')) {
                $secretNames['EasyDmarcApiKeyVaultSecret']
            }
            else { 'EasyDMARC-API-Key' }
        $ApiKey = Get-ImperionKeyVaultSecret -Name $keyVaultSecretName
    }
    if (-not $ApiKey) {
        throw 'EasyDMARC API key unavailable: pass -ApiKey, provision the SecretStore secret named by EasyDmarcApiKey, or the Key Vault secret named by EasyDmarcApiKeyVaultSecret (issue #122).'
    }
    return $ApiKey
}
