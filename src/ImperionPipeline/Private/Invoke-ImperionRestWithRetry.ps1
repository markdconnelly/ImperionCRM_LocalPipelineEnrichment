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

    # Secret-bearing URLs exist (KQM passes ?apikey= in the querystring, issue #98) — any
    # log line or thrown message uses this redacted form, never the raw $Uri.
    $safeUri = $Uri -replace '(?i)([?&](?:apikey|api[_-]?key|key|sig|signature|token|secret|password)=)[^&]+', '${1}REDACTED'

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        # Transport is isolated in Invoke-ImperionHttp so this retry policy is unit-testable.
        $resp = Invoke-ImperionHttp -Uri $Uri -Headers $Headers -Method $Method -Body $Body -ContentType $ContentType
        $status = $resp.Status

        if ($status -ge 200 -and $status -lt 300) {
            return $resp
        }

        if ($status -in 429, 503, 504 -and $attempt -lt $MaxAttempts) {
            $retryAfter = 0
            if ($resp.Headers -and $resp.Headers['Retry-After']) {
                [int]::TryParse(([string]$resp.Headers['Retry-After'][0]), [ref]$retryAfter) | Out-Null
            }
            if ($retryAfter -le 0) { $retryAfter = [math]::Min([math]::Pow(2, $attempt), 60) }
            Write-ImperionLog -Level Warn -Source 'http' -Message "Throttled ($status) on $safeUri; retrying in ${retryAfter}s (attempt $attempt/$MaxAttempts)."
            Start-Sleep -Seconds $retryAfter
            continue
        }

        throw "HTTP $status calling $Method $safeUri. Body: $($resp.Body | ConvertTo-Json -Compress -Depth 4)"
    }
    throw "Exhausted $MaxAttempts attempts calling $Method $safeUri."
}
