function Get-ImperionAutotaskContext {
    <#
    .SYNOPSIS
        Resolve Autotask auth headers + zone base URL from the SecretStore (private).
    .DESCRIPTION
        One place that maps the SecretStore secret names to the Autotask REST auth headers
        (ApiIntegrationCode / UserName / Secret) and discovers the account zone, so every
        autotask get-layer collector shares the same credential handling. Returns
        [pscustomobject]@{ Headers; ApiBase }. Requires Initialize-ImperionContext.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $names = Get-ImperionSecretNames
    $atUser = Get-ImperionSecretValue -Name $names.AutotaskUserName
    $headers = @{
        ApiIntegrationCode = (Get-ImperionSecretValue -Name $names.AutotaskIntegrationCode)
        UserName           = $atUser
        Secret             = (Get-ImperionSecretValue -Name $names.AutotaskSecret)
        'Content-Type'     = 'application/json'
    }
    $apiBase = Get-ImperionAutotaskZone -UserName $atUser -Headers $headers
    [pscustomobject]@{ Headers = $headers; ApiBase = $apiBase }
}
