function Invoke-ImperionRestWithRetry {
    <#
    .SYNOPSIS
        Single REST call with 429/503 backoff honoring Retry-After. Private core for all API wrappers.
    .DESCRIPTION
        Returns a PSCustomObject { Body; Status; Headers }. Does not throw on handled
        throttling; throws on exhausted retries or unexpected 4xx/5xx so callers fail loudly.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Uri,
        [hashtable] $Headers = @{},
        [string] $Method = 'GET',
        $Body,
        [string] $ContentType = 'application/json',
        [int] $MaxAttempts = 6
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
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

        $body = Invoke-RestMethod @params

        if ($status -ge 200 -and $status -lt 300) {
            return [pscustomobject]@{ Body = $body; Status = $status; Headers = $respHeaders }
        }

        if ($status -in 429, 503, 504 -and $attempt -lt $MaxAttempts) {
            $retryAfter = 0
            if ($respHeaders -and $respHeaders['Retry-After']) {
                [int]::TryParse(([string]$respHeaders['Retry-After'][0]), [ref]$retryAfter) | Out-Null
            }
            if ($retryAfter -le 0) { $retryAfter = [math]::Min([math]::Pow(2, $attempt), 60) }
            Write-ImperionLog -Level Warn -Source 'http' -Message "Throttled ($status) on $Uri; retrying in ${retryAfter}s (attempt $attempt/$MaxAttempts)."
            Start-Sleep -Seconds $retryAfter
            continue
        }

        throw "HTTP $status calling $Method $Uri. Body: $($body | ConvertTo-Json -Compress -Depth 4)"
    }
    throw "Exhausted $MaxAttempts attempts calling $Method $Uri."
}
