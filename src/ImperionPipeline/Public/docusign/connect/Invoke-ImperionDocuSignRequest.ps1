function Invoke-ImperionDocuSignRequest {
    <#
    .SYNOPSIS
        GET a DocuSign eSignature REST collection with bearer auth, following nextUri paging.
    .DESCRIPTION
        Reusable connect-layer helper (CLAUDE.md §4) for the DocuSign eSignature REST API
        (v2.1). Auth is `Authorization: Bearer <accessToken>`; collection responses carry
        their items under a named property (e.g. `envelopes`) and the next page under
        `nextUri` — a RELATIVE path ("/accounts/{id}/envelopes?...start_position=100")
        resolved against -ResolveBaseUri. Pure and StrictMode-safe: the token is passed in
        (SecretStore secret `docusign-token`), so the function holds no secret and is
        mockable.

        CONFIRM BEFORE LIVE USE: the account-server base URL (na/eu pod), the token's
        grant flow (the stored token is OAuth user/JWT-consent output and EXPIRES —
        operator refresh or a JWT-grant follow-up issue), and the nextUri shape are
        ASSUMPTIONS (local-pipeline ADR-0005 flagged DocuSign "no API access yet") —
        verify on the first real pull.
    .PARAMETER AccessToken
        DocuSign OAuth access token, sent as the bearer credential.
    .PARAMETER Uri
        Full request URL (base + path) for the first page.
    .PARAMETER ResolveBaseUri
        Origin used to resolve a relative nextUri (e.g. 'https://na4.docusign.net/restapi/v2.1').
        Defaults to the scheme+authority+/restapi/v2.1 derived from -Uri.
    .PARAMETER ItemsProperty
        Dotted path to the collection in the response body. Default 'envelopes'. If
        absent, the whole body is returned as a single item.
    .PARAMETER NextLinkProperty
        Dotted path to the next-page URI. Default 'nextUri'.
    .EXAMPLE
        Invoke-ImperionDocuSignRequest -AccessToken $token -Uri "$base/accounts/$acct/envelopes?from_date=2000-01-01"
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string] $AccessToken,
        [Parameter(Mandatory)][string] $Uri,
        [string] $ResolveBaseUri,
        [string] $ItemsProperty = 'envelopes',
        [string] $NextLinkProperty = 'nextUri'
    )

    if (-not $ResolveBaseUri) {
        $parsed = [uri]$Uri
        $ResolveBaseUri = '{0}://{1}/restapi/v2.1' -f $parsed.Scheme, $parsed.Authority
    }

    $headers = @{ Authorization = "Bearer $AccessToken"; Accept = 'application/json' }
    $items = [System.Collections.Generic.List[object]]::new()
    $next = $Uri
    while ($next) {
        if ($next -notmatch '^https?://') {
            $next = '{0}/{1}' -f $ResolveBaseUri.TrimEnd('/'), $next.TrimStart('/')
        }
        $resp = Invoke-ImperionRestWithRetry -Uri $next -Headers $headers -Method GET
        $collection = Get-ImperionPropertyPath -InputObject $resp.Body -Path $ItemsProperty
        if ($null -ne $collection) { $collection | ForEach-Object { $items.Add($_) } }
        elseif ($null -ne $resp.Body) { $items.Add($resp.Body) }   # single resource / non-paged shape
        $next = Get-ImperionPropertyPath -InputObject $resp.Body -Path $NextLinkProperty
    }
    return $items.ToArray()
}
