function Edit-ImperionOkfConceptFile {
    <#
    .SYNOPSIS
        Apply column-NAME-only drift deltas to one OKF concept file's '## Schema' table and bump its
        frontmatter timestamp — in place, on a local checkout of the front-end bundle.
    .DESCRIPTION
        The mechanical half of the drift agent's PR-opener (issue #190): given the add/remove column
        deltas Get-ImperionSemanticDrift computed (NAMES only — never DDL, never a type, never a value,
        never PII; CLAUDE.md sections 8 & 11), edit the matching concept file the front-end maintainer
        would otherwise edit by hand:

          - ADD a live-but-undocumented column: append a row to the '## Schema' markdown table with the
            column name backtick-wrapped, a placeholder `_(?)_` type, and a TODO note pointing the human
            at the live read-only DB to fill in shape/meaning. The agent does NOT invent a type or prose
            (that stays human — keep authoring out of scope, issue #190).
          - REMOVE a documented-but-gone column: drop its '## Schema' row.
          - Bump the frontmatter `timestamp:` to the supplied ISO-8601 instant (the staleness signal).

        It edits ONLY the file path it is handed (a clone the caller owns); it never edits this repo's
        copy and never forks the canon. Pure text transform on a file — hermetic, no DB, no network,
        so it is unit-testable without a clone or a token. Returns $true if the file changed.

        It deliberately touches nothing but the '## Schema' rows and the timestamp: the definition,
        source-of-record, joins and PII prose are the maintainer's to write (the proposal links ADR-0086
        and tells them to verify against the live DB).
    .PARAMETER Path
        Absolute path to the concept file (…/semantic-layer/tables/<Concept>.md) in the caller's clone.
    .PARAMETER AddedColumns
        Live-but-undocumented column NAMES to add as new '## Schema' rows.
    .PARAMETER RemovedColumns
        Documented-but-gone column NAMES whose '## Schema' rows are dropped.
    .PARAMETER Timestamp
        ISO-8601 instant to write into the frontmatter `timestamp:` (e.g. 2026-06-15T00:00:00Z).
    .EXAMPLE
        Edit-ImperionOkfConceptFile -Path $f -AddedColumns health_score -RemovedColumns legacy_col -Timestamp $ts
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Edits a file in a caller-owned temp clone; the only externally-visible effect (the PR) is gated upstream behind -Execute + a token.')]
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string] $Path,
        [string[]] $AddedColumns = @(),
        [string[]] $RemovedColumns = @(),
        [Parameter(Mandatory)][string] $Timestamp
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-ImperionLog -Level Warn -Source 'semantic' -Message "Concept file not found, skipped: $Path"
        return $false
    }

    # Column NAMES only ever cross the boundary. Defensively reject anything that is not a plain
    # identifier (no spaces / pipes / backticks) so a malformed delta can never inject markdown or DDL.
    $safeName = { param($n) $n -and ($n -match '^[A-Za-z_][A-Za-z0-9_]*$') }
    $toAdd = [string[]]@($AddedColumns | Where-Object { & $safeName $_ } | ForEach-Object { $_.ToLowerInvariant() })
    $toRemove = [string[]]@($RemovedColumns | Where-Object { & $safeName $_ } | ForEach-Object { $_.ToLowerInvariant() })

    $lines = [System.Collections.Generic.List[string]]::new()
    Get-Content -LiteralPath $Path -ErrorAction Stop | ForEach-Object { $lines.Add($_) }

    $changed = $false

    # 1) Bump the frontmatter timestamp (first `timestamp:` inside the opening '---' fence).
    $inFront = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $l = $lines[$i]
        if ($l.Trim() -eq '---') { if ($inFront) { break } else { $inFront = $true; continue } }
        if ($inFront -and $l -match '^\s*timestamp:\s*(.+?)\s*$') {
            if ($Matches[1] -ne $Timestamp) { $lines[$i] = "timestamp: $Timestamp"; $changed = $true }
            break
        }
    }

    # 2) Locate the '## Schema' table: its bounds and the last data row (for appends).
    $inSchema = $false
    $lastDataRow = -1
    $removeIndexes = [System.Collections.Generic.List[int]]::new()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $l = $lines[$i]
        if ($l -match '^\s*##\s') { $inSchema = ($l -match '^\s*##\s+Schema\s*$'); continue }
        if (-not $inSchema) { continue }
        if ($l -notmatch '^\s*\|') { continue }                 # not a table row
        if ($l -match '^\s*\|\s*-{2,}') { $lastDataRow = $i; continue }   # separator counts as a floor
        $first = ($l -split '\|')[1]
        if ($null -eq $first) { continue }
        if ($first -match '`([^`]+)`') {
            $lastDataRow = $i
            $name = $Matches[1].Trim().ToLowerInvariant()
            if ($toRemove -contains $name) { $removeIndexes.Add($i) }
        }
    }

    # 3) Apply removals (descending so indexes stay valid), then appends after the last row.
    foreach ($idx in ($removeIndexes | Sort-Object -Descending)) {
        $lines.RemoveAt($idx)
        if ($idx -le $lastDataRow) { $lastDataRow-- }
        $changed = $true
    }

    if ($toAdd.Count -and $lastDataRow -ge 0) {
        $insertAt = $lastDataRow + 1
        foreach ($name in $toAdd) {
            $lines.Insert($insertAt, "| ``$name`` | _(?)_ | TODO: live silver column undocumented in OKF — confirm type/meaning against the live read-only DB (CLAUDE.md section 8). |")
            $insertAt++
            $changed = $true
        }
    }
    elseif ($toAdd.Count) {
        Write-ImperionLog -Level Warn -Source 'semantic' -Message "No '## Schema' table found in $Path; added columns not applied: $($toAdd -join ', ')"
    }

    if ($changed) {
        # Preserve the file's trailing-newline convention; write LF-joined UTF-8 (no BOM).
        $text = ($lines -join "`n")
        if (-not $text.EndsWith("`n")) { $text += "`n" }
        [System.IO.File]::WriteAllText($Path, $text, [System.Text.UTF8Encoding]::new($false))
    }

    return $changed
}
