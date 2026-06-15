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
          - The actual `gh`/REST PR-push is a documented STUB (see NOTE below) tracked as a
            follow-up; today -Execute files an ISSUE on the front-end repo via `gh` so the drift is
            visible and human-actionable without the agent ever holding push rights.
    .PARAMETER Drift
        Drift rows from Get-ImperionSemanticDrift (only non-'in-sync' rows are acted on).
    .PARAMETER Execute
        Opt in to live execution (open an issue on the front-end repo). Default: dry-run only.
    .PARAMETER TargetRepo
        owner/repo of the front-end canon. Default markdconnelly/ImperionCRM.
    .EXAMPLE
        $p = New-ImperionSemanticDriftProposal -Drift $drift           # dry-run; inspect $p.Body
    .EXAMPLE
        New-ImperionSemanticDriftProposal -Drift $drift -Execute       # gated: opens an issue
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
    [void]$sb.AppendLine('_Column names only — verify shape/meaning against the live read-only DB (CLAUDE.md §8) before merging. Refs ADR-0086, LocalPipelineEnrichment #175._')

    $title = ('docs(semantic-layer): sync OKF bundle to silver drift ({0} concept(s))' -f $actionable.Count)
    $body = $sb.ToString()

    $opened = $false
    if ($Execute) {
        # Fail-closed: live execution needs a token. Never prompt; never store/print it.
        if (-not $env:IMPERION_GH_TOKEN) {
            Write-ImperionLog -Level Warn -Source 'semantic' -Message 'Semantic-drift proposal NOT opened: IMPERION_GH_TOKEN unset (fail-closed). Re-run with the token to open the cross-repo issue.'
            return [pscustomobject]@{ Title = $title; Body = $body; Concepts = @($actionable.concept); Opened = $false }
        }

        # NOTE (follow-up): the full design opens a cross-repo PR with the concept files already
        # edited on a branch in the front-end repo. That requires a clone+branch+push of
        # markdconnelly/ImperionCRM and is deferred to a follow-up issue. Until then -Execute files
        # an ISSUE on the front-end repo (human-actionable, agent holds no push rights). This stub
        # is intentionally the conservative half of issue #175's scope.
        try {
            $env:GH_TOKEN = $env:IMPERION_GH_TOKEN   # gh reads GH_TOKEN; scoped to this process only.
            & gh issue create --repo $TargetRepo --title $title --body $body --label 'needs-triage' | Out-Null
            $opened = $LASTEXITCODE -eq 0
            if (-not $opened) { Write-ImperionLog -Level Error -Source 'semantic' -Message "gh issue create failed (exit $LASTEXITCODE)." }
        }
        catch {
            Write-ImperionLog -Level Error -Source 'semantic' -Message "Semantic-drift proposal failed to open: $($_.Exception.Message)"
        }
        finally {
            Remove-Item Env:\GH_TOKEN -ErrorAction SilentlyContinue   # do not leave the token in the environment.
        }
    }

    [pscustomobject]@{ Title = $title; Body = $body; Concepts = @($actionable.concept); Opened = $opened }
}
