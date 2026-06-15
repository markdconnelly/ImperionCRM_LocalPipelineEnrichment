function Update-ImperionCoverageMatrixTimestamp {
    <#
    .SYNOPSIS
        Bump the frontmatter `timestamp:` of the OKF bundle's coverage-matrix.md on a local checkout.
    .DESCRIPTION
        System CLAUDE.md section 11 requires any silver-shape change to touch the matching
        `coverage-matrix.md` row in the same change set. The matrix rows are LINKS
        (`[concept](tables/concept.md)`), not column lists — there is no column-level delta to apply to a
        row, so the agent's mechanical, PII-free signal is to bump the matrix's frontmatter timestamp,
        flagging the maintainer to re-review the affected rows. (Authoring archetype / ICM-workflow prose
        stays human — issue #190 keeps prose out of scope.)

        Pure text transform on the caller's clone; never edits this repo's copy, never forks the canon.
        Hermetic — no DB, no network. Returns $true if the timestamp changed.
    .PARAMETER Path
        Absolute path to coverage-matrix.md in the caller's clone of the front-end bundle.
    .PARAMETER Timestamp
        ISO-8601 instant to write (e.g. 2026-06-15T00:00:00Z).
    .EXAMPLE
        Update-ImperionCoverageMatrixTimestamp -Path $m -Timestamp $ts
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Edits a file in a caller-owned temp clone; the only externally-visible effect (the PR) is gated upstream behind -Execute + a token.')]
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Timestamp
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-ImperionLog -Level Warn -Source 'semantic' -Message "Coverage matrix not found, skipped: $Path"
        return $false
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    Get-Content -LiteralPath $Path -ErrorAction Stop | ForEach-Object { $lines.Add($_) }

    $changed = $false
    $inFront = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $l = $lines[$i]
        if ($l.Trim() -eq '---') { if ($inFront) { break } else { $inFront = $true; continue } }
        if ($inFront -and $l -match '^\s*timestamp:\s*(.+?)\s*$') {
            if ($Matches[1] -ne $Timestamp) { $lines[$i] = "timestamp: $Timestamp"; $changed = $true }
            break
        }
    }

    if ($changed) {
        $text = ($lines -join "`n")
        if (-not $text.EndsWith("`n")) { $text += "`n" }
        [System.IO.File]::WriteAllText($Path, $text, [System.Text.UTF8Encoding]::new($false))
    }

    return $changed
}
