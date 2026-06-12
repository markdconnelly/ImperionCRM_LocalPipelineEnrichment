function Resolve-ImperionKqmApiKey {
    <#
    .SYNOPSIS
        Resolve the KQM API key: explicit value, else SecretStore mirror, else Key Vault original.
    .DESCRIPTION
        Module-internal key resolution shared by the KQM get layer (issue #98), mirroring
        the Voyage pattern (ADR-0009): an explicit -ApiKey wins; else the SecretStore
        secret named by `KqmApiKey` when the vault is unlocked this run; else the Key
        Vault secret named by `KqmApiKeyVaultSecret` (default `KQM-API-Key`, the operator-
        provisioned original in kv-imperioncrm-prd) read by the cert SP. The value is
        returned to the caller and never logged; KQM URLs carry it as ?apikey=, so the
        querystring redaction in Invoke-ImperionRestWithRetry is the second guard.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $ApiKey)

    if ($ApiKey) { return $ApiKey }
    $secretNames = Get-ImperionSecretNames
    if ($script:ImperionSecretStoreVault -and
        $secretNames -is [System.Collections.IDictionary] -and $secretNames.Contains('KqmApiKey')) {
        $ApiKey = Get-ImperionSecretValue -Name $secretNames['KqmApiKey']
    }
    if (-not $ApiKey) {
        $keyVaultSecretName =
            if ($secretNames -is [System.Collections.IDictionary] -and $secretNames.Contains('KqmApiKeyVaultSecret')) {
                $secretNames['KqmApiKeyVaultSecret']
            }
            else { 'KQM-API-Key' }
        $ApiKey = Get-ImperionKeyVaultSecret -Name $keyVaultSecretName
    }
    return $ApiKey
}
