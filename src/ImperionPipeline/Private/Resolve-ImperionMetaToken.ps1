function Resolve-ImperionMetaToken {
    <#
    .SYNOPSIS
        Resolve the Meta Business Manager system-user token: explicit value, else SecretStore.
    .DESCRIPTION
        Module-internal token resolution shared by the meta connect/get layer (issue #126),
        mirroring Resolve-ImperionKqmApiKey exactly (the KQM/Voyage pattern, ADR-0009): an
        explicit -Token wins; else the SecretStore mirror named by `MetaSystemUserToken`
        (default 'meta-system-user-token') when the vault is unlocked this run; else the
        Key Vault original named by `MetaTokenVaultSecret` (default 'Meta-SystemUser-Token',
        operator-provisioned in kv-imperioncrm-prd) read by the cert SP — the interim path
        until the server's SecretStore bootstrap (#102) mirrors it locally (ADR-0013).
        The value is returned to the caller and never logged. The connect layer carries it
        as an Authorization: Bearer header (never the querystring), and strips Meta's
        access_token parameter from paging URLs as the second guard.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $Token)

    if ($Token) { return $Token }
    $secretNames = Get-ImperionSecretNames
    if ($script:ImperionSecretStoreVault -and
        $secretNames -is [System.Collections.IDictionary] -and $secretNames.Contains('MetaSystemUserToken')) {
        $Token = Get-ImperionSecretValue -Name $secretNames['MetaSystemUserToken']
    }
    if (-not $Token) {
        $keyVaultSecretName =
            if ($secretNames -is [System.Collections.IDictionary] -and $secretNames.Contains('MetaTokenVaultSecret')) {
                $secretNames['MetaTokenVaultSecret']
            }
            else { 'Meta-SystemUser-Token' }
        $Token = Get-ImperionKeyVaultSecret -Name $keyVaultSecretName
    }
    if (-not $Token) {
        throw 'Meta system-user token unavailable: pass -Token, provision the SecretStore secret named by MetaSystemUserToken, or the Key Vault secret named by MetaTokenVaultSecret (ADR-0013).'
    }
    return $Token
}
