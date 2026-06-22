function Invoke-ImperionSemanticDriftSync {
    <#
    .SYNOPSIS
        Detect silver-vs-OKF semantic drift and (gated) open a cross-repo proposal against the
        front-end OKF bundle.
    .DESCRIPTION
        The scheduled-task entry point for issue #175 / ADR-0086. It:
          1. Resolves a LOCAL, read-only copy of the front-end semantic-layer bundle (the front end
             owns the canon, CLAUDE.md section 11 — this repo never forks the files). Pass -BundlePath
             for an existing checkout, or let it shallow-clone markdconnelly/ImperionCRM to a temp dir.
          2. Runs Get-ImperionSemanticDrift (column NAMES only — no data, no PII).
          3. Logs a per-status summary so a no-op run is auditable ("nothing drifted, moved on").
          4. Hands non-in-sync drift to New-ImperionSemanticDriftProposal. Without -Execute this is a
             DRY RUN (proposal built + logged, nothing opened). With -Execute it opens the proposal
             on the front-end repo — fail-closed: needs IMPERION_GH_TOKEN or it logs a Warn and exits.

        DORMANT by default: a cold node with no bundle and no token does a clean no-op. Requires
        Initialize-ImperionContext for the DB read. Never stores or prints secrets.
    .PARAMETER BundlePath
        Existing local checkout of the front-end semantic-layer dir. If omitted, the bundle is
        shallow-cloned read-only to a temp directory (requires git + read access to the repo).
    .PARAMETER Execute
        Open the proposal on the front-end repo. Default: dry-run (detect + log only).
    .EXAMPLE
        Invoke-ImperionSemanticDriftSync                       # dry-run; logs drift, opens nothing
    .EXAMPLE
        Invoke-ImperionSemanticDriftSync -BundlePath $b -Execute
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'External effect (opening a proposal) is itself gated behind -Execute + a token; ShouldProcess would duplicate that gate.')]
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [string] $BundlePath,
        [switch] $Execute,
        [string] $SourceRepo = 'https://github.com/markdconnelly/ImperionCRM.git'
    )

    $started = Get-Date

    # One canon for resolving the front-end bundle (shared with Invoke-ImperionSemanticConceptSync, #176).
    $resolved = Resolve-ImperionOkfBundle -BundlePath $BundlePath -SourceRepo $SourceRepo
    $cleanup = $resolved.Cleanup

    try {
        if ($resolved.Reason -eq 'clone-failed') {
            Write-ImperionLog -Level Warn -Source 'semantic' -Message 'Semantic-drift sync skipped: could not clone the front-end bundle (no access / git unavailable). Fail-closed no-op.'
            return @()
        }
        if ($resolved.Reason -eq 'no-bundle') {
            Write-ImperionLog -Level Warn -Source 'semantic' -Message "Semantic-drift sync skipped: no OKF bundle at '$($resolved.BundlePath)'."
            return @()
        }
        $BundlePath = $resolved.BundlePath

        $drift = Get-ImperionSemanticDrift -BundlePath $BundlePath
        $byStatus = $drift | Group-Object status | ForEach-Object { "$($_.Name)=$($_.Count)" }
        Write-ImperionLog -Level Metric -Source 'semantic' -Message 'Semantic drift evaluated.' -Data @{ summary = ($byStatus -join ' ') }

        $proposal = New-ImperionSemanticDriftProposal -Drift $drift -Execute:$Execute
        if ($proposal.Concepts.Count -gt 0) {
            $state = if ($proposal.Opened) { "opened ($($proposal.Mode))" } elseif ($Execute) { 'NOT opened (fail-closed)' } else { 'built (dry-run)' }
            Write-ImperionLog -Level Metric -Source 'semantic' -Message ('Semantic-drift proposal {0}.' -f $state) -Data @{ concepts = ($proposal.Concepts -join ','); opened = $proposal.Opened; mode = $proposal.Mode; url = $proposal.Url }
        }

        return $drift
    }
    finally {
        if ($cleanup -and (Test-Path $cleanup)) { Remove-Item -Recurse -Force $cleanup -ErrorAction SilentlyContinue }
        Write-ImperionLog -Level Metric -Source 'semantic' -Message 'Semantic-drift sync complete.' -Data @{ seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 1); execute = [bool]$Execute }
    }
}
