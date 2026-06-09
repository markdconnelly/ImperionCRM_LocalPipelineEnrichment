function Invoke-ImperionHttp {
    <#
    .SYNOPSIS
        Make a single HTTP call and return { Body; Status; Headers } (private transport).
    .DESCRIPTION
        Isolates Invoke-RestMethod's out-variables (-StatusCodeVariable / -ResponseHeadersVariable)
        into one place so the retry/backoff policy in Invoke-ImperionRestWithRetry is a pure,
        unit-testable function over a normal return value. Does not throw on HTTP error status
        (uses -SkipHttpErrorCheck); the caller decides what to do with the status. $status /
        $respHeaders are pre-initialized so a provider that returns no status can't trip
        StrictMode.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string] $Uri,
        [hashtable] $Headers = @{},
        [string] $Method = 'GET',
        $Body,
        [string] $ContentType = 'application/json'
    )

    $params = @{
        Uri                     = $Uri
        Headers                 = $Headers
        Method                  = $Method
        SkipHttpErrorCheck      = $true
        StatusCodeVariable      = 'status'
        ResponseHeadersVariable = 'respHeaders'
        ErrorAction             = 'Stop'
    }
    if ($null -ne $Body) { $params.Body = $Body; $params.ContentType = $ContentType }

    $status = $null
    $respHeaders = $null
    $responseBody = Invoke-RestMethod @params
    [pscustomobject]@{ Body = $responseBody; Status = $status; Headers = $respHeaders }
}
