function Invoke-ImperionDarkWebIdRequest {
    <#
    .SYNOPSIS
        GET a Dark Web ID (ID Agent) API collection with HTTP Basic auth, following pagination.
    .DESCRIPTION
        Reusable connect-layer helper (CLAUDE.md §4). Aligned with the cloud Pipeline's Dark Web
        ID client (ImperionCRM_Pipeline src/shared/clients/darkwebid.ts, ADR-0040). Dark Web ID
        (Kaseya / ID Agent) authenticates with HTTP Basic auth — a username + password pair sent
        as `Authorization: Basic <base64(username:password)>` against base
        `https://secure.darkwebid.com` (with IP allowlisting), NOT a bearer API key. Responses are
        JSON:API-style: records under `data`, the next-page URL under `links.next`. Pure and
        StrictMode-safe: the credentials are passed in (a company credential — the
        `{username, password}` blob in Key Vault `conn-company-darkwebid`), so the function holds
        no secret and is mockable.
    .PARAMETER Username
        Dark Web ID account username, the user half of the Basic auth pair.
    .PARAMETER Password
        Dark Web ID account password, the password half of the Basic auth pair.
    .PARAMETER Uri
        Full request URL (base + path), e.g. https://secure.darkwebid.com/compromises?page[size]=100.
    .PARAMETER ItemsProperty
        Dotted path to the collection in the response body. Default 'data'. If absent, the whole
        body is returned as a single item.
    .PARAMETER NextLinkProperty
        Dotted path to the next-page URL (cursor). Default 'links.next' (JSON:API).
    .EXAMPLE
        Invoke-ImperionDarkWebIdRequest -Username $user -Password $pass -Uri 'https://secure.darkwebid.com/compromises?page[size]=100'
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    # Dark Web ID's API genuinely authenticates with an HTTP Basic username+password pair (Kaseya
    # docs); the credentials are resolved upstream from Key Vault and passed in as the wire values,
    # so [pscredential]/SecureString would only force a plaintext round-trip here. Same string
    # posture as every other connector's ApiKey/AccessToken param (CLAUDE.md §4).
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingUsernameAndPasswordParams', '')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'Password')]
    param(
        [Parameter(Mandatory)][string] $Username,
        [Parameter(Mandatory)][string] $Password,
        [Parameter(Mandatory)][string] $Uri,
        [string] $ItemsProperty = 'data',
        [string] $NextLinkProperty = 'links.next'
    )

    $pair  = '{0}:{1}' -f $Username, $Password
    $basic = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pair))
    $headers = @{ Authorization = "Basic $basic"; Accept = 'application/json' }
    $items = [System.Collections.Generic.List[object]]::new()
    $next = $Uri
    while ($next) {
        $resp = Invoke-ImperionRestWithRetry -Uri $next -Headers $headers -Method GET
        $collection = Get-ImperionPropertyPath -InputObject $resp.Body -Path $ItemsProperty
        if ($null -ne $collection) { $collection | ForEach-Object { $items.Add($_) } }
        elseif ($null -ne $resp.Body) { $items.Add($resp.Body) }   # single resource / non-paged shape
        $next = Get-ImperionPropertyPath -InputObject $resp.Body -Path $NextLinkProperty
    }
    return $items.ToArray()
}
