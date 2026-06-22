function Resolve-ImperionOkfBundle {
    <#
    .SYNOPSIS
        Resolve a LOCAL, read-only copy of the front-end OKF semantic-layer bundle.
    .DESCRIPTION
        One canon for locating the bundle the front end owns (markdconnelly/ImperionCRM at
        docs/database/semantic-layer, CLAUDE.md section 11 / ADR-0086 — this repo never forks
        the files). Shared by every cross-repo bundle consumer so they agree on resolution and
        fail-closed behaviour: the semantic-drift agent (Invoke-ImperionSemanticDriftSync, #175)
        and the OKF concept vectorizer (Invoke-ImperionSemanticConceptSync, #176).

        With -BundlePath it validates an existing checkout. Without one it shallow-clones the
        front-end repo (just enough to read the bundle) to a temp directory and returns that dir
        in .Cleanup so the caller removes it after the run (the caller owns the bundle for the
        whole run, so cleanup cannot happen here).

        Pure resolution: it does not log (callers log under their own source label) and it never
        writes the canon. Hermetic when -BundlePath is supplied — no git, no network.
    .PARAMETER BundlePath
        Existing local checkout of the front-end semantic-layer dir (the one containing tables/).
        If omitted, the bundle is shallow-cloned read-only to a temp directory.
    .PARAMETER SourceRepo
        Clone URL of the front-end repo when -BundlePath is omitted.
    .OUTPUTS
        [pscustomobject] with:
          Reason     'ok' | 'clone-failed' | 'no-bundle'
          BundlePath the resolved (or attempted) semantic-layer dir
          TablesPath <BundlePath>/tables when Reason='ok', else $null
          Cleanup    a temp dir the caller must Remove-Item after the run, or $null
    .EXAMPLE
        $b = Resolve-ImperionOkfBundle -BundlePath 'C:\…\semantic-layer'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $BundlePath,
        [string] $SourceRepo = 'https://github.com/markdconnelly/ImperionCRM.git'
    )

    $cleanup = $null

    if (-not $BundlePath) {
        # Shallow, read-only clone of just enough of the front-end repo to read the bundle.
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("imperion-okf-{0}" -f ([guid]::NewGuid().ToString('N')))
        & git clone --depth 1 --quiet $SourceRepo $tmp 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tmp)) {
            return [pscustomobject]@{ Reason = 'clone-failed'; BundlePath = $null; TablesPath = $null; Cleanup = $null }
        }
        $cleanup = $tmp
        $BundlePath = Join-Path $tmp 'docs/database/semantic-layer'
    }

    $tablesPath = Join-Path $BundlePath 'tables'
    if (-not (Test-Path $tablesPath)) {
        return [pscustomobject]@{ Reason = 'no-bundle'; BundlePath = $BundlePath; TablesPath = $null; Cleanup = $cleanup }
    }

    [pscustomobject]@{ Reason = 'ok'; BundlePath = $BundlePath; TablesPath = $tablesPath; Cleanup = $cleanup }
}
