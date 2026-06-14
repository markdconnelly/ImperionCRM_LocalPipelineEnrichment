function Invoke-ImperionQboRequest {
    <#
    .SYNOPSIS
        Query a QuickBooks Online entity with OAuth2 bearer auth, paging STARTPOSITION/MAXRESULTS.
    .DESCRIPTION
        Reusable connect-layer helper (CLAUDE.md §4) for the QuickBooks Online (Intuit)
        Accounting API v3 read path. QBO exposes a single SQL-like **query** endpoint:
        GET {base}/v3/company/{realmId}/query?query=<url-encoded SQL>&minorversion=N with
        `Authorization: Bearer <accessToken>`. Results come back wrapped:
        `{ QueryResponse: { <Entity>: [ ... ], startPosition, maxResults }, time }`.

        Paging is done IN the query text — `... STARTPOSITION <n> MAXRESULTS <p>` — so this
        helper owns the loop: it appends the clause, walks pages of -PageSize, and stops on
        a short page (fewer than -PageSize rows). -MaxPages caps a runaway loop. The bearer
        token is passed in (the get layer reads it from the SecretStore secret
        `qbo-access-token`), so this function holds no secret and is mockable/StrictMode-safe.

        CONFIRM BEFORE LIVE USE (local-pipeline ADR for QBO; gated on Mark's app
        registration — the same blocker as backend #104): the production base host
        (`quickbooks.api.intuit.com` vs `sandbox-quickbooks.api.intuit.com`), the minor
        version, and the exact QueryResponse wrapper/entity-property casing are modeled from
        the documented API but UNVERIFIED against the real company until the registration
        lands. Tolerate both the wrapped shape and a bare array pending that verification.
    .PARAMETER AccessToken
        QBO OAuth2 access token, sent as the bearer credential. Held only in memory; QBO
        tokens EXPIRE (~1h) and the refresh token rotates — see docs/integrations/quickbooks-online.md.
    .PARAMETER BaseUri
        QBO API origin. Default production 'https://quickbooks.api.intuit.com'.
    .PARAMETER RealmId
        The QBO company id (realm) — Imperion's own books. Path-segment of every request.
    .PARAMETER Query
        The base SQL-like statement WITHOUT a STARTPOSITION/MAXRESULTS clause, e.g.
        "SELECT * FROM BillPayment WHERE MetaData.LastUpdatedTime > '2026-06-01T00:00:00-00:00'".
    .PARAMETER EntityProperty
        The property under QueryResponse holding the rows (e.g. 'BillPayment').
    .PARAMETER PageSize
        Rows per page (QBO max 1000). A page with fewer rows ends the loop.
    .PARAMETER MaxPages
        Safety cap on pages per call.
    .PARAMETER MinorVersion
        QBO API minor version querystring (forward-compat). Confirm against the live app.
    .EXAMPLE
        Invoke-ImperionQboRequest -AccessToken $t -RealmId $realm -EntityProperty 'BillPayment' `
            -Query "SELECT * FROM BillPayment"
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)][string] $AccessToken,
        [string] $BaseUri = 'https://quickbooks.api.intuit.com',
        [Parameter(Mandatory)][string] $RealmId,
        [Parameter(Mandatory)][string] $Query,
        [Parameter(Mandatory)][string] $EntityProperty,
        [ValidateRange(1, 1000)][int] $PageSize = 100,
        [ValidateRange(1, 1000)][int] $MaxPages = 200,
        [int] $MinorVersion = 70
    )

    $headers = @{ Authorization = "Bearer $AccessToken"; Accept = 'application/json' }
    $items = [System.Collections.Generic.List[object]]::new()

    for ($page = 0; $page -lt $MaxPages; $page++) {
        $startPosition = ($page * $PageSize) + 1
        $pagedQuery = '{0} STARTPOSITION {1} MAXRESULTS {2}' -f $Query.TrimEnd(), $startPosition, $PageSize
        $uri = '{0}/v3/company/{1}/query?query={2}&minorversion={3}' -f `
            $BaseUri.TrimEnd('/'), [uri]::EscapeDataString($RealmId), [uri]::EscapeDataString($pagedQuery), $MinorVersion

        $resp = Invoke-ImperionRestWithRetry -Uri $uri -Headers $headers -Method GET

        # Tolerate the documented wrapper (QueryResponse.<Entity>) and, pending live
        # verification, a bare array body. The @(if) keeps $pageItems a real array even when
        # the page is empty (StrictMode-safe).
        $collection = Get-ImperionPropertyPath -InputObject $resp.Body -Path ('QueryResponse.{0}' -f $EntityProperty)
        if ($null -eq $collection) { $collection = Get-ImperionPropertyPath -InputObject $resp.Body -Path $EntityProperty }
        $pageItems = @(if ($null -ne $collection) { $collection })
        foreach ($item in $pageItems) { $items.Add($item) }
        if ($pageItems.Count -lt $PageSize) { break }
    }
    return $items.ToArray()
}
