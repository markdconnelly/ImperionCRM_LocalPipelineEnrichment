function Resolve-ImperionAmazonBusinessToken {
    <#
    .SYNOPSIS
        Resolve the Amazon Business access token: explicit value, else SecretStore mirror, else Key Vault original.
    .DESCRIPTION
        Module-internal token resolution shared by the Amazon Business get layer (issue #198),
        mirroring Resolve-ImperionEasyDmarcApiKey / Resolve-ImperionMetaToken exactly (the
        KQM/Voyage pattern, ADR-0009): an explicit -Token wins; else the SecretStore secret named
        by `AmazonBusinessToken` (default 'amazon-business-token') when the vault is unlocked this
        run; else the Key Vault secret named by `AmazonBusinessTokenVaultSecret` (default
        'AmazonBusiness-Token', the operator-provisioned original in kv-imperioncrm-prd) read by
        the cert SP. Amazon Business is a COMPANY credential — Imperion's own purchasing account,
        not a per-client key.

        The value is returned to the caller and never logged; the connect layer sends it as an
        `Authorization: Bearer` header (NOT the querystring), so request URLs are not
        secret-bearing. GATED: until the token is provisioned (Mark-gated, plan must include API
        access), this throws and the scheduled task logs the gap and exits cleanly.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string] $Token)

    if ($Token) { return $Token }
    $secretNames = Get-ImperionSecretNames
    if ($script:ImperionSecretStoreVault -and
        $secretNames -is [System.Collections.IDictionary] -and $secretNames.Contains('AmazonBusinessToken')) {
        $Token = Get-ImperionSecretValue -Name $secretNames['AmazonBusinessToken']
    }
    if (-not $Token) {
        $keyVaultSecretName =
            if ($secretNames -is [System.Collections.IDictionary] -and $secretNames.Contains('AmazonBusinessTokenVaultSecret')) {
                $secretNames['AmazonBusinessTokenVaultSecret']
            }
            else { 'AmazonBusiness-Token' }
        $Token = Get-ImperionKeyVaultSecret -Name $keyVaultSecretName
    }
    if (-not $Token) {
        throw 'Amazon Business access token unavailable: pass -Token, provision the SecretStore secret named by AmazonBusinessToken, or the Key Vault secret named by AmazonBusinessTokenVaultSecret (issue #198).'
    }
    return $Token
}
