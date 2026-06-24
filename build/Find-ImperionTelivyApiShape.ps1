#Requires -Version 7.2
<#
.SYNOPSIS
    SECRET-SAFE discovery probe for the unverified Telivy API constants (issue #312).
.DESCRIPTION
    `Imperion-TelivyAssessments` throws exit 1 and `televy_reports` bronze stays empty because
    the Telivy connect-helper constants (base URL, auth header, resource path, items property)
    are UNVERIFIED placeholders, and a web search found no public Telivy API docs — so there is
    no known-good source to copy. Guess-fixing those constants is the exact placeholder-drift
    trap (memory `imperion-lp-vendor-connect-drift`), so this script does NOT change any
    constant. Instead it sweeps a small matrix of (base URL x auth header x path) candidates and
    reports, per combination, ONLY:

        - the combo label (which base/header/path was tried),
        - the HTTP status code (or a transport error class — e.g. DNS/TLS),
        - the SHAPE of the response body: its top-level JSON key NAMES (never values), or, for an
          array body, `array[N]` plus the first element's key NAMES.

    From that output, the working host/header/path/items-property become obvious (a 200 whose
    body has a `data` array of report-shaped objects), and the real fix — correcting the
    constants in `Invoke-ImperionTelivyRequest` / `Get-ImperionTelivyReport` + the cloud client
    `televy.ts`, then verifying a live pull — lands in a normal #297-style PR.

    SECRET SAFETY (the whole point):
      * The API key is resolved via the module's `Resolve-ImperionTelivyApiKey` (credential
        registry, #291) and is ONLY ever placed into a request header. It is NEVER written to the
        console, a log, a file, or an error message.
      * Only HTTP STATUS CODES and response KEY NAMES are printed — never any body VALUE (which
        could carry client PII) and never the key.
      * Read-only: every request is a GET. Nothing is written anywhere.

    Run on the host that holds the Telivy credential (the on-prem box) — the credential is not
    reachable from a dev machine. Requires `Initialize-ImperionContext` to have unlocked the vault.
.PARAMETER MaxKeysShown
    Cap on how many top-level key names to print per response (defensive; default 25).
.EXAMPLE
    pwsh ./build/Find-ImperionTelivyApiShape.ps1
    # then read the table: the row that is 200 with a report-shaped `data` array is the answer.
#>
[CmdletBinding()]
param(
    [int] $MaxKeysShown = 25
)

$ErrorActionPreference = 'Stop'

# Bring the module + resolver + config into scope, then pull the key into a local that is only
# ever handed to a header hashtable. Never echo $apiKey.
Import-Module (Join-Path $PSScriptRoot '..' 'src' 'ImperionPipeline' 'ImperionPipeline.psd1') -Force
$apiKey = Resolve-ImperionTelivyApiKey
if ([string]::IsNullOrWhiteSpace($apiKey)) {
    throw 'Telivy API key did not resolve. Run Initialize-ImperionContext first (and confirm conn-company-televy is provisioned, #291).'
}

# The candidate matrix. These are the plausible constants to discriminate between — NOT a fix.
# Keep it small and bounded; widen by editing this list, never by guessing into the live code.
$baseUrls = @(
    'https://api.telivy.com'
    'https://api.telivy.com/v1'
    'https://app.telivy.com/api'
    'https://api.telivy.io'
)
$paths = @(
    '/reports'
    '/reports?page[size]=100'
    '/v1/reports'
    '/assessments'
)
# Each auth style is a scriptblock that returns a fresh header hashtable for the resolved key.
$authStyles = @(
    @{ Label = 'x-api-key';      Build = { param($k) @{ 'x-api-key' = $k; Accept = 'application/json' } } }
    @{ Label = 'Bearer';         Build = { param($k) @{ Authorization = "Bearer $k"; Accept = 'application/json' } } }
    @{ Label = 'Authorization';  Build = { param($k) @{ Authorization = $k; Accept = 'application/json' } } }
)

function Get-ImperionBodyShape {
    # Return a short, VALUE-FREE description of a parsed JSON body: top-level key names, or
    # array[N] + first element's key names. Never returns any value from the body.
    param($Body, [int] $MaxKeys)
    if ($null -eq $Body) { return '(empty body)' }
    if ($Body -is [System.Array]) {
        $first = if ($Body.Count -gt 0) { $Body[0] } else { $null }
        $keys = if ($first -is [pscustomobject]) { ($first.psobject.Properties.Name | Select-Object -First $MaxKeys) -join ',' } else { '(scalar items)' }
        return ('array[{0}] first-item-keys: {1}' -f $Body.Count, $keys)
    }
    if ($Body -is [pscustomobject]) {
        return 'object keys: ' + (($Body.psobject.Properties.Name | Select-Object -First $MaxKeys) -join ',')
    }
    return '(scalar body)'
}

Write-Host ''
Write-Host 'Telivy API-shape probe — STATUS + response KEY NAMES only. No key, no body values, GET-only.'
Write-Host ('{0,-34} {1,-14} {2,-26} {3}' -f 'BASE', 'AUTH', 'PATH', 'RESULT')
Write-Host ('-' * 110)

foreach ($base in $baseUrls) {
    foreach ($auth in $authStyles) {
        foreach ($path in $paths) {
            $uri = ('{0}{1}' -f $base.TrimEnd('/'), $path)
            $headers = & $auth.Build $apiKey
            $result = $null
            try {
                # -SkipHttpErrorCheck: 4xx/5xx return a response instead of throwing, so we can
                # report the status. Short timeout keeps the full sweep quick.
                $resp = Invoke-WebRequest -Uri $uri -Headers $headers -Method GET -SkipHttpErrorCheck -TimeoutSec 15 -MaximumRedirection 2
                $shape = '(unparseable body)'
                if ($resp.Content) {
                    try { $shape = Get-ImperionBodyShape -Body ($resp.Content | ConvertFrom-Json) -MaxKeys $MaxKeysShown }
                    catch { $shape = '(non-JSON body)' }
                }
                $result = ('HTTP {0}  {1}' -f [int]$resp.StatusCode, $shape)
            }
            catch {
                # Transport-level failure (DNS, TLS, timeout). Print the EXCEPTION TYPE only —
                # never the message, which could echo the URL with a querystring or other detail.
                $result = ('ERR  {0}' -f $_.Exception.GetType().Name)
            }
            finally {
                # Drop the per-iteration header reference holding the key as soon as we are done.
                $headers = $null
            }
            Write-Host ('{0,-34} {1,-14} {2,-26} {3}' -f $base, $auth.Label, $path, $result)
        }
    }
}

# Best-effort scrub of the local key reference.
$apiKey = $null
[System.GC]::Collect()

Write-Host ''
Write-Host 'Read the 200 row whose body is a report-shaped `data` array — that base/header/path/items'
Write-Host 'property is the answer. Apply it as a #297-style fix to Invoke-ImperionTelivyRequest +'
Write-Host 'Get-ImperionTelivyReport + the cloud client televy.ts, then verify a live pull (#312).'
