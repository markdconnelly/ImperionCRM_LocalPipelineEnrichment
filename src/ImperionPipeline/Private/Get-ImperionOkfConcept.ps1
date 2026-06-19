function Get-ImperionOkfConcept {
    <#
    .SYNOPSIS
        Parse one OKF concept file's documented column set + frontmatter timestamp.
    .DESCRIPTION
        The OKF concept file (ADR-0086) is markdown + YAML-ish frontmatter. Its '## Schema'
        section is a markdown table whose first column is the backtick-wrapped column name
        (e.g. `| `health_score` | numeric | ... |`). This parser extracts:
          - Columns  : the ordered list of documented column names (lower-cased, de-backticked)
          - Timestamp: the frontmatter `timestamp:` value (drift staleness signal)
          - Exists   : whether the file was found at all (missing-concept = a silver entity with
                       no concept file yet)

        It reads ONLY the local copy of the bundle the caller hands it (a path); it never writes
        and never forks the file into this repo (CLAUDE.md section 11 — one canon, owned by the
        front end). Pure text parsing: hermetic, no DB, no network.
    .PARAMETER Path
        Absolute path to the concept file (…/semantic-layer/tables/<Concept>.md).
    .EXAMPLE
        Get-ImperionOkfConcept -Path 'C:\…\semantic-layer\tables\account.md'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ Exists = $false; Columns = [string[]]@(); Timestamp = $null; HasAuthority = $false }
    }

    $lines = Get-Content -LiteralPath $Path -ErrorAction Stop

    # Frontmatter timestamp (first `timestamp:` before the second '---' fence).
    $timestamp = $null
    $inFront = $false
    foreach ($l in $lines) {
        if ($l.Trim() -eq '---') { if ($inFront) { break } else { $inFront = $true; continue } }
        if ($inFront -and $l -match '^\s*timestamp:\s*(.+?)\s*$') { $timestamp = $Matches[1]; break }
    }

    # Walk the '## Schema' table; the column name is the first cell, backtick-wrapped.
    $columns = [System.Collections.Generic.List[string]]::new()
    $inSchema = $false
    foreach ($l in $lines) {
        if ($l -match '^\s*##\s') {
            $inSchema = $l -match '^\s*##\s+Schema\s*$'
            continue
        }
        if (-not $inSchema) { continue }
        # A table data row starts with '|'; skip the header/separator rows.
        if ($l -notmatch '^\s*\|') { continue }
        if ($l -match '^\s*\|\s*-{2,}') { continue }            # separator row
        $first = ($l -split '\|')[1]                            # cell between 1st and 2nd pipe
        if ($null -eq $first) { continue }
        if ($first -match '`([^`]+)`') {                        # backtick-wrapped name only
            $columns.Add($Matches[1].Trim().ToLowerInvariant())
        }
    }

    # Authority dimension (ADR-0104 §6, layer 3): does the concept actually STATE its
    # source-of-record / authority rule? The orchestrator grounds on this section before
    # acting; a concept that documents shape but not authority is the load-bearing gap the
    # reconciliation backstop surfaces. True when the '## Source of record / authority'
    # heading is present AND followed by at least one non-blank line.
    $hasAuthority = $false
    $inAuthority = $false
    foreach ($l in $lines) {
        if ($l -match '^\s*##\s') {
            $inAuthority = $l -match '^\s*##\s+Source of record\s*/\s*authority\s*$'
            continue
        }
        if ($inAuthority -and $l.Trim() -ne '') { $hasAuthority = $true; break }
    }

    [pscustomobject]@{
        Exists       = $true
        Columns      = [string[]]$columns.ToArray()
        Timestamp    = $timestamp
        HasAuthority = $hasAuthority
    }
}
