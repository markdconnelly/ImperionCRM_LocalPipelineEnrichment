function New-ImperionSemanticDriftPullRequest {
    <#
    .SYNOPSIS
        Open a cross-repo PR on the front-end OKF bundle with the drifted concept files already edited
        on a branch — the real PR-opener that promotes the issue-filing stub (issue #190, ADR-0086).
    .DESCRIPTION
        Given the actionable drift rows and the proposal Title/Body New-ImperionSemanticDriftProposal
        built, this:
          1. CLONES markdconnelly/ImperionCRM read-only via the token to a temp dir the caller owns.
          2. CHECKS OUT a feature branch (chore/okf-drift-<utc>) off the default branch.
          3. EDITS each affected concept file's '## Schema' table (column NAMES only) and bumps its
             frontmatter timestamp (Edit-ImperionOkfConceptFile); bumps coverage-matrix.md's timestamp
             (Update-ImperionCoverageMatrixTimestamp). 'missing-concept' / 'orphaned-concept' need human
             authoring/reconciliation, so they are LISTED in the PR body but not auto-edited.
          4. COMMITS, PUSHES the branch, and opens a PR with `gh pr create` (the ADR-0086 body).

        Security guarantees preserved (CLAUDE.md sections 8 & 11):
          - The token is scoped to write a FEATURE BRANCH only and is read from $env:IMPERION_GH_TOKEN
            by reference. It is handed to git ONLY via an in-memory remote URL and to `gh` via $env:GH_TOKEN,
            both scrubbed in `finally`. It is never written to disk, never logged, never a CLI argument.
          - Only column NAMES and concept-file paths cross the boundary — no DDL, no row data, no PII.
          - The agent NEVER merges: it opens the PR for human review and stops.

        DRY-RUN: with -WhatIf the clone/branch/edit happens in the caller's temp dir, the diff is logged,
        but the push and `gh pr create` are SKIPPED — so the branch-and-edit core is exercisable (and
        tested) without ever touching the remote. The caller is responsible for the temp dir lifecycle;
        this returns the local clone path so a dry-run caller can inspect or clean it.
    .PARAMETER Drift
        Actionable (non-'in-sync') drift rows from Get-ImperionSemanticDrift.
    .PARAMETER Title
        The PR title (a conventional commit; reused as the commit subject).
    .PARAMETER Body
        The ADR-0086-conformant PR body New-ImperionSemanticDriftProposal built.
    .PARAMETER TargetRepo
        owner/repo of the front-end canon. Default markdconnelly/ImperionCRM.
    .PARAMETER Timestamp
        ISO-8601 instant stamped into every edited file. Default: now (UTC).
    .OUTPUTS
        pscustomobject @{ Opened; Url; Branch; ClonePath; EditedConcepts }
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '',
        Justification = 'Reads a token from an env var by reference only; never declared as a parameter, never logged, scrubbed in finally.')]
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object[]] $Drift,
        [Parameter(Mandatory)][string] $Title,
        [Parameter(Mandatory)][string] $Body,
        [string] $TargetRepo = 'markdconnelly/ImperionCRM',
        [string] $Timestamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    )

    $result = [pscustomobject]@{ Opened = $false; Url = $null; Branch = $null; ClonePath = $null; EditedConcepts = @() }

    # Fail-closed: no token, no PR. Never prompt, never store/print it.
    if (-not $env:IMPERION_GH_TOKEN) {
        Write-ImperionLog -Level Warn -Source 'semantic' -Message 'Semantic-drift PR NOT opened: IMPERION_GH_TOKEN unset (fail-closed).'
        return $result
    }

    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("imperion-okf-pr-{0}" -f ([guid]::NewGuid().ToString('N')))
    $result.ClonePath = $tmp
    $branch = "chore/okf-drift-{0}" -f ([datetime]::UtcNow.ToString('yyyyMMddHHmmss'))
    $result.Branch = $branch

    try {
        # Token-bearing remote URL is built in memory and never logged. git stores no credential.
        $remote = "https://x-access-token:$($env:IMPERION_GH_TOKEN)@github.com/$TargetRepo.git"

        & git clone --depth 1 --quiet $remote $tmp 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tmp)) {
            Write-ImperionLog -Level Error -Source 'semantic' -Message 'Semantic-drift PR NOT opened: clone of the front-end repo failed (token scope / access).'
            return $result
        }

        & git -C $tmp checkout -q -b $branch 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-ImperionLog -Level Error -Source 'semantic' -Message "Semantic-drift PR NOT opened: could not create branch $branch."
            return $result
        }

        $bundle = Join-Path $tmp 'docs/database/semantic-layer'
        $tablesDir = Join-Path $bundle 'tables'
        $matrix = Join-Path $bundle 'coverage-matrix.md'
        $edited = [System.Collections.Generic.List[string]]::new()

        foreach ($d in $Drift) {
            # Only 'drift' rows carry mechanical column deltas. missing/orphaned need human authoring —
            # they are described in the PR body, not auto-edited.
            if ($d.status -ne 'drift') { continue }
            $file = Join-Path $tablesDir ("{0}.md" -f $d.concept)
            $didEdit = Edit-ImperionOkfConceptFile -Path $file `
                -AddedColumns ([string[]]@($d.added_columns)) `
                -RemovedColumns ([string[]]@($d.removed_columns)) `
                -Timestamp $Timestamp
            if ($didEdit) { $edited.Add($d.concept) }
        }

        if ($edited.Count -eq 0) {
            Write-ImperionLog -Level Warn -Source 'semantic' -Message 'Semantic-drift PR NOT opened: no concept files changed (only missing/orphaned concepts, which need human authoring). Falling back to an issue is the caller''s choice.'
            return $result
        }

        [void](Update-ImperionCoverageMatrixTimestamp -Path $matrix -Timestamp $Timestamp)
        $result.EditedConcepts = @($edited.ToArray())

        & git -C $tmp add docs/database/semantic-layer 2>$null | Out-Null

        if (-not $PSCmdlet.ShouldProcess($TargetRepo, "push branch '$branch' and open a PR")) {
            # Dry-run: show what WOULD ship; do not push, do not open a PR.
            $diffStat = (& git -C $tmp diff --cached --stat 2>$null) -join "`n"
            Write-ImperionLog -Level Metric -Source 'semantic' -Message 'Semantic-drift PR dry-run (WhatIf): branch + edits staged, not pushed.' -Data @{ branch = $branch; concepts = ($edited -join ','); diffstat = $diffStat }
            return $result
        }

        # Commit as the agent identity; the token's owner is the GitHub author.
        & git -C $tmp -c user.name='imperion-okf-drift-agent' -c user.email='okf-drift-agent@users.noreply.github.com' commit -q -m $Title 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-ImperionLog -Level Error -Source 'semantic' -Message 'Semantic-drift PR NOT opened: commit failed.'
            return $result
        }

        & git -C $tmp push -q --set-upstream origin $branch 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-ImperionLog -Level Error -Source 'semantic' -Message "Semantic-drift PR NOT opened: push of $branch failed (token scope?)."
            return $result
        }

        # Open the PR (never merge). `gh` reads GH_TOKEN; scoped to this process, scrubbed in finally.
        $env:GH_TOKEN = $env:IMPERION_GH_TOKEN
        $url = & gh pr create --repo $TargetRepo --head $branch --title $Title --body $Body --label 'needs-triage' 2>$null
        if ($LASTEXITCODE -eq 0 -and $url) {
            $result.Opened = $true
            $result.Url = ("$url").Trim()
        }
        else {
            Write-ImperionLog -Level Error -Source 'semantic' -Message "Semantic-drift PR push succeeded but `gh pr create` failed (exit $LASTEXITCODE)."
        }
        return $result
    }
    catch {
        Write-ImperionLog -Level Error -Source 'semantic' -Message "Semantic-drift PR failed: $($_.Exception.Message)"
        return $result
    }
    finally {
        Remove-Item Env:\GH_TOKEN -ErrorAction SilentlyContinue   # never leave the token in the environment
        # Clean the clone unless this was a dry-run (a -WhatIf caller may want to inspect it).
        if (-not $WhatIfPreference -and $tmp -and (Test-Path $tmp)) {
            Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
        }
    }
}
