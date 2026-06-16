function Resolve-ImperionCdwApiKey {
    <#
    .SYNOPSIS
        Resolve the CDW API key: explicit value, else SecretStore mirror, else Key Vault original.
    .DESCRIPTION
        Module-internal key resolution shared by the CDW get layer (issue #198), mirroring
        Resolve-ImperionEasyDmarcApiKey / Resolve-ImperionMetaToken exactly (the KQM/Voyage pattern,
        ADR-0009): an explicit -ApiKey wins; else the SecretStore secret named by `CdwApiKey`
        (default 'cdw-api-key') when the vault is unlocked this run; else the Key Vault secret named
        by `CdwApiKeyVaultSecret` (default 'CDW-API-Key', the operator-provisioned original in
        kv-imperioncrm-prd) read by the cert SP. CDW is a COMPANY credential — Imperion's own
        purchasing account, not a per-client key.

        The value is returned to the caller and never logged; the connect layer sends it as an
        `Authorization: Bearer` header (NOT the querystring), so request URLs are not
        secret-bearing. GATED: until the key is provisioned (Mark-gated, plan must include API
        access), this throws and the scheduled task logs the gap and exits cleanly.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $ApiKey)

    if ($ApiKey) { return $ApiKey }
    $secretNames = Get-ImperionSecretNames
    if ($script:ImperionSecretStoreVault -and
        $secretNames -is [System.Collections.IDictionary] -and $secretNames.Contains('CdwApiKey')) {
        $ApiKey = Get-ImperionSecretValue -Name $secretNames['CdwApiKey']
    }
    if (-not $ApiKey) {
        $keyVaultSecretName =
            if ($secretNames -is [System.Collections.IDictionary] -and $secretNames.Contains('CdwApiKeyVaultSecret')) {
                $secretNames['CdwApiKeyVaultSecret']
            }
            else { 'CDW-API-Key' }
        $ApiKey = Get-ImperionKeyVaultSecret -Name $keyVaultSecretName
    }
    if (-not $ApiKey) {
        throw 'CDW API key unavailable: pass -ApiKey, provision the SecretStore secret named by CdwApiKey, or the Key Vault secret named by CdwApiKeyVaultSecret (issue #198).'
    }
    return $ApiKey
}
