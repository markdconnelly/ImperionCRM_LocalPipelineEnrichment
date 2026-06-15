function New-ImperionSemanticDriftProposal {
    <#
    .SYNOPSIS
        Build the markdown body of a cross-repo proposal from detected semantic drift, and (when
        live execution is enabled + a token is present) open it against markdconnelly/ImperionCRM.
    .DESCRIPTION
        The drift agent PROPOSES; humans approve (ADR-0086 constraint, issue #175). This function
        turns drift rows (from Get-ImperionSemanticDrift) into a precise, PII-free proposal that a
        front-end maintainer applies to the OKF bundle: which concept file to touch, which columns
        to add/remove from its '## Schema' table, and a reminder to bump the frontmatter timestamp.

        It only ever emits column NAMES and concept-file paths — never schema DDL, never row data,
        never client identifiers (CLAUDE.md sections 8 & 11). It NEVER writes into this repo and
        NEVER edits the bundle directly: the front end owns the canon; the agent's output is a PR
        or an issue against the front-end repo for human review.

        Live execution is DORMANT / fail-closed:
          - Without -Execute, it returns the proposal object (Title/Body/Concepts) and does nothing
            external — the default, safe in CI and on a cold node.
          - With -Execute, it requires a GitHub token in $env:IMPERION_GH_TOKEN. If absent it
            LOGS a Warn and EXITS cleanly (fail-closed; never prompts, never stores/prints a token).
          - With -Execute + token, it opens a cross-repo **PR** with the affected concept files
            already edited on a branch (New-ImperionSemanticDriftPullRequest, issue #190): column-name
            deltas applied to each '## Schema' table, frontmatter timestamps bumped, coverage-matrix
            timestamp bumped. The agent NEVER merges. (Issue #190 promoted the earlier issue-filing
            stub to this PR-opener.) When the only drift is 'missing-concept' / 'orphaned-concept'
            (no mechanical edit to make — those need human authoring/reconciliation) it falls back to
            filing an ISSUE so the drift is still visible and human-actionable.
    .PARAMETER Drift
        Drift rows from Get-ImperionSemanticDrift (only non-'in-sync' rows are acted on).
    .PARAMETER Execute
        Opt in to live execution (open a PR — or, for author-only drift, an issue — on the front-end
        repo). Default: dry-run only.
    .PARAMETER TargetRepo
        owner/repo of the front-end canon. Default markdconnelly/ImperionCRM.
    .EXAMPLE
        $p = New-ImperionSemanticDriftProposal -Drift $drift           # dry-run; inspect $p.Body
    .EXAMPLE
        New-ImperionSemanticDriftProposal -Drift $drift -Execute       # gated: opens a cross-repo PR
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '',
        Justification = 'Reads a token from an env var by reference only; never declared as a parameter, never logged.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'The only external effect (opening a proposal) is itself gated behind -Execute + a token; ShouldProcess would duplicate that gate.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object[]] $Drift,
        [switch] $Execute,
        [string] $TargetRepo = 'markdconnelly/ImperionCRM'
    )

    $actionable = @($Drift | Where-Object status -ne 'in-sync')
    if ($actionable.Count -eq 0) {
        return [pscustomobject]@{ Title = $null; Body = $null; Concepts = @(); Opened = $false }
    }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('## OKF semantic-layer drift detected')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('The on-prem enrichment drift agent (LocalPipelineEnrichment #175) compared the')
    [void]$sb.AppendLine('live silver schema (column names only — no data, no PII) to the OKF bundle at')
    [void]$sb.AppendLine('`docs/database/semantic-layer/` and found drift. Per ADR-0086 the agent proposes;')
    [void]$sb.AppendLine('a maintainer applies the change in the front-end repo and bumps each concept''s')
    [void]$sb.AppendLine('frontmatter `timestamp` (and the matching `coverage-matrix.md` row).')
    [void]$sb.AppendLine('')

    foreach ($d in $actionable) {
        $rel = ('tables/{0}.md' -f $d.concept)
        [void]$sb.AppendLine(('### `{0}` — {1}' -f $d.concept, $d.status))
        switch ($d.status) {
            'missing-concept' {
                [void]$sb.AppendLine(('- Live silver relation `{0}` has no concept file. **Author** `{1}` (ADR-0086 frontmatter + definition / source-of-record / schema / joins / PII note).' -f $d.relation, $rel))
            }
            'orphaned-concept' {
                [void]$sb.AppendLine(('- Concept `{0}` exists but live relation `{1}` is gone/renamed. **Reconcile** (rename or retire the file).' -f $rel, $d.relation))
            }
            default {
                if ($d.added_columns.Count) {
                    [void]$sb.AppendLine(('- **Add to `{0}` `## Schema`** (live, undocumented): {1}' -f $rel, (($d.added_columns | ForEach-Object { "``$_``" }) -join ', ')))
                }
                if ($d.removed_columns.Count) {
                    [void]$sb.AppendLine(('- **Remove from `{0}` `## Schema`** (documented, no longer present): {1}' -f $rel, (($d.removed_columns | ForEach-Object { "``$_``" }) -join ', ')))
                }
            }
        }
        [void]$sb.AppendLine('')
    }
    [void]$sb.AppendLine('_Column names only — verify shape/meaning against the live read-only DB (CLAUDE.md §8) before merging. The agent opened this for review; it does **not** merge. Refs ADR-0086, LocalPipelineEnrichment #175/#190._')

    $title = ('docs(semantic-layer): sync OKF bundle to silver drift ({0} concept(s))' -f $actionable.Count)
    $body = $sb.ToString()

    # Rows carrying a mechanical column delta (added/removed) can be auto-edited onto a branch → PR.
    # missing-concept / orphaned-concept need human authoring/reconciliation, so they only ever
    # produce an issue.
    $editable = @($actionable | Where-Object { $_.status -eq 'drift' })

    $opened = $false
    $url = $null
    $mode = 'dry-run'
    if ($Execute) {
        # Fail-closed: live execution needs a token. Never prompt; never store/print it.
        if (-not $env:IMPERION_GH_TOKEN) {
            Write-ImperionLog -Level Warn -Source 'semantic' -Message 'Semantic-drift proposal NOT opened: IMPERION_GH_TOKEN unset (fail-closed). Re-run with the token to open the cross-repo PR.'
            return [pscustomobject]@{ Title = $title; Body = $body; Concepts = @($actionable.concept); Opened = $false; Url = $null; Mode = 'fail-closed' }
        }

        if ($editable.Count -gt 0) {
            # Promote (issue #190): open a cross-repo PR with the concept files already edited on a branch.
            $mode = 'pr'
            $pr = New-ImperionSemanticDriftPullRequest -Drift $editable -Title $title -Body $body -TargetRepo $TargetRepo
            $opened = [bool]$pr.Opened
            $url = $pr.Url
            if ($opened) { Write-ImperionLog -Level Metric -Source 'semantic' -Message 'Semantic-drift PR opened (no merge).' -Data @{ url = $url; concepts = ($pr.EditedConcepts -join ',') } }
        }
        else {
            # Only author-required drift (missing/orphaned): no file to edit → file an issue instead.
            $mode = 'issue'
            try {
                $env:GH_TOKEN = $env:IMPERION_GH_TOKEN   # gh reads GH_TOKEN; scoped to this process only.
                $issueUrl = & gh issue create --repo $TargetRepo --title $title --body $body --label 'needs-triage' 2>$null
                $opened = $LASTEXITCODE -eq 0
                if ($opened) { $url = ("$issueUrl").Trim() }
                else { Write-ImperionLog -Level Error -Source 'semantic' -Message "gh issue create failed (exit $LASTEXITCODE)." }
            }
            catch {
                Write-ImperionLog -Level Error -Source 'semantic' -Message "Semantic-drift proposal failed to open: $($_.Exception.Message)"
            }
            finally {
                Remove-Item Env:\GH_TOKEN -ErrorAction SilentlyContinue   # do not leave the token in the environment.
            }
        }
    }

    [pscustomobject]@{ Title = $title; Body = $body; Concepts = @($actionable.concept); Opened = $opened; Url = $url; Mode = $mode }
}
