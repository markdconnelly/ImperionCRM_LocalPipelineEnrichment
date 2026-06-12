function Resolve-ImperionMetaToken {
    <#
    .SYNOPSIS
        Resolve the Meta Business Manager system-user token: explicit value, else SecretStore.
    .DESCRIPTION
        Module-internal token resolution shared by the meta connect/get layer (issue #126),
        mirroring Resolve-ImperionKqmApiKey with ONE deliberate difference: there is NO Key
        Vault fallback. The Business Manager SYSTEM-USER token (non-expiring) is custodied
        on-prem only — the SecretStore secret named by `MetaSystemUserToken` (default
        'meta-system-user-token', ADR-0013). An explicit -Token wins; else the SecretStore
        when the vault is unlocked this run; else a loud throw the scheduled task gates on.
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
        throw 'Meta system-user token unavailable: pass -Token or provision the SecretStore secret named by MetaSystemUserToken (no Key Vault fallback - on-prem custody only, ADR-0013).'
    }
    return $Token
}
