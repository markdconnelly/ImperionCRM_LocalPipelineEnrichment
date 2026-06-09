function Get-ImperionKeyVaultSecret {
    <#
    .SYNOPSIS
        Read a secret value from Azure Key Vault using the cert-backed Entra SP (ADR-0002/§2).
    .DESCRIPTION
        Connect-layer reader for COMPANY credentials that live in Key Vault rather than the
        local SecretStore — e.g. the Dark Web ID API key (`conn-company-darkwebid`, ADR-0040).
        Mints a short-lived Key Vault data-plane token via the certificate SP (the app holds
        `Key Vault Secrets User`, CLAUDE.md §2) and GETs the secret over TLS. The value is
        returned but never logged or persisted. Requires Initialize-ImperionContext.
    .PARAMETER Name
        The Key Vault secret name.
    .PARAMETER VaultUri
        Vault base URI (e.g. https://my-kv.vault.azure.net). Defaults to config KeyVault.VaultUri.
    .PARAMETER ApiVersion
        Key Vault data-plane api-version. Default 7.4.
    .OUTPUTS
        The secret value (string).
    .EXAMPLE
        $key = Get-ImperionKeyVaultSecret -Name 'conn-company-darkwebid'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string] $Name,
        [string] $VaultUri,
        [string] $ApiVersion = '7.4'
    )

    $cfg = Get-ImperionConfig
    if (-not $VaultUri -and ($cfg -is [System.Collections.IDictionary]) -and $cfg.Contains('KeyVault')) {
        $VaultUri = $cfg['KeyVault'].VaultUri
    }
    if (-not $VaultUri) {
        throw 'No Key Vault URI: pass -VaultUri or set KeyVault.VaultUri in pipeline.config.psd1.'
    }

    $token = Get-ImperionKeyVaultToken
    $uri = '{0}/secrets/{1}?api-version={2}' -f $VaultUri.TrimEnd('/'), [uri]::EscapeDataString($Name), $ApiVersion
    $resp = Invoke-ImperionRestWithRetry -Uri $uri -Headers @{ Authorization = "Bearer $token" } -Method GET
    $value = Get-ImperionMember $resp.Body 'value'
    if ($null -eq $value) { throw "Key Vault secret '$Name' returned no value from $VaultUri." }
    return $value
}
