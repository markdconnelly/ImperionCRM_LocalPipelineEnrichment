function Invoke-ImperionPostureSnapshot {
    <#
    .SYNOPSIS
        Write immutable Imperion Secure Score snapshots (posture_snapshot + pillars) per account.
    .DESCRIPTION
        The quarterly half of frontend ADR-0051 §5 (this repo's ADR-0011, issue #89):
        for each in-scope account, reads its mapped tenants' tenant_posture rollups
        (LEFT JOIN — a mapped-but-never-merged tenant still counts, as a row of NULLs,
        matching the frontend read model), computes Score Model v1 via
        Get-ImperionSecureScore (the parity-pinned twin of the frontend's
        imperion-score.ts), and INSERTs one posture_snapshot row + one
        posture_snapshot_pillar row per model pillar inside a single transaction.

        Snapshots are APPEND-ONLY: this cmdlet only ever INSERTs (migration 0063
        enforces it by grant — the pipeline role holds no UPDATE/DELETE). Composite,
        grade, and model version are stored at capture and never recomputed.

        CADENCE: the Imperion-PostureSnapshot task runs DAILY (03:40, after the 03:20
        posture merge) but the cmdlet gates itself to CALENDAR QUARTERS — a scheduled
        run skips any account that already has a 'scheduled' snapshot in the current
        quarter (DB clock, date_trunc('quarter', now())). The daily cadence makes the
        quarter boundary self-healing: a server that was off on Jan 1 snapshots on
        Jan 2. On-demand and business-review triggers bypass the gate.

        Account scope: every account with at least one Tenant Mapping (account_tenant);
        pass -AccountId to snapshot specific accounts regardless of mapping state.
        A failing account rolls back its own transaction and never blocks the fleet.
        Requires Initialize-ImperionContext.
    .PARAMETER AccountId
        Optional account subset (uuid strings). Default: all accounts with >=1 tenant
        mapping.
    .PARAMETER Trigger
        Snapshot trigger recorded on the row: 'scheduled' (default; quarter-gated),
        'on_demand', or 'business_review'.
    .PARAMETER BusinessReviewId
        The strategic_business_review id that triggered this snapshot. Required with
        -Trigger business_review, forbidden otherwise.
    .PARAMETER Connection
        Optional open Npgsql connection to reuse; otherwise one is opened and disposed.
    .EXAMPLE
        Invoke-ImperionPostureSnapshot
    .EXAMPLE
        Invoke-ImperionPostureSnapshot -AccountId $id -Trigger on_demand
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string[]] $AccountId,
        [ValidateSet('scheduled', 'on_demand', 'business_review')]
        [string] $Trigger = 'scheduled',
        [string] $BusinessReviewId,
        $Connection
    )

    if ($Trigger -eq 'business_review' -and -not $BusinessReviewId) {
        throw "Trigger 'business_review' requires -BusinessReviewId (every QBR snapshot links its review)."
    }
    if ($BusinessReviewId -and $Trigger -ne 'business_review') {
        throw "-BusinessReviewId is only valid with -Trigger business_review."
    }

    $started = Get-Date
    $ownConnection = -not $Connection
    if ($ownConnection) { $Connection = New-ImperionDbConnection }

    try {
        if (-not $AccountId) {
            # Default scope: accounts that have at least one Tenant Mapping. Accounts
            # with no mapped tenants would snapshot all-uncovered F-grades forever —
            # noise, not signal; reach them explicitly via -AccountId if ever needed.
            $AccountId = @(Invoke-ImperionDbQuery -Connection $Connection `
                    -Sql 'SELECT DISTINCT account_id FROM account_tenant ORDER BY account_id' |
                    ForEach-Object { "$($_.account_id)" })
        }

        $skipped = 0
        if ($Trigger -eq 'scheduled' -and @($AccountId).Count -gt 0) {
            # Calendar-quarter gate, on the DB clock: an account with a scheduled
            # snapshot this quarter is done until the next quarter starts.
            $alreadySnapshotted = @(Invoke-ImperionDbQuery -Connection $Connection -Sql @"
SELECT DISTINCT account_id FROM posture_snapshot
 WHERE trigger = 'scheduled'
   AND date_trunc('quarter', taken_at) = date_trunc('quarter', now())
"@ | ForEach-Object { "$($_.account_id)" })
            $remaining = @($AccountId | Where-Object { $_ -notin $alreadySnapshotted })
            $skipped = @($AccountId).Count - $remaining.Count
            $AccountId = $remaining
        }

        if (@($AccountId).Count -eq 0) {
            Write-ImperionLog -Source 'posture' -Message 'Posture snapshot: nothing to do (no mapped accounts, or all snapshotted this quarter).' -Data @{
                skipped = $skipped
            }
            return
        }

        $snapshotted = 0
        $failed = 0

        foreach ($account in $AccountId) {
            if (-not $PSCmdlet.ShouldProcess($account, 'Take posture snapshot')) { continue }

            $transaction = $Connection.BeginTransaction()
            try {
                # The account's rollups, LEFT JOIN so every mapped tenant surfaces —
                # the same shape the frontend's at-a-glance card reads.
                $rollups = @(Invoke-ImperionDbQuery -Connection $Connection -Sql @"
SELECT tp.secure_score_current, tp.secure_score_max, tp.licensed_user_count,
       COALESCE(tp.policies_compliant, 0)  AS policies_compliant,
       COALESCE(tp.policies_drift, 0)      AS policies_drift,
       COALESCE(tp.policies_ungoverned, 0) AS policies_ungoverned,
       COALESCE(tp.policies_missing, 0)    AS policies_missing,
       COALESCE(tp.exposures_open, 0)      AS exposures_open,
       tp.refreshed_at
  FROM account_tenant m
  LEFT JOIN tenant_posture tp ON tp.tenant_id = m.tenant_id
 WHERE m.account_id = @a::uuid
"@ -Parameters @{ a = $account })

                $score = Get-ImperionSecureScore -TenantPosture $rollups

                # APPEND-ONLY: INSERTs only, by design and by grant (migration 0063).
                $snapshotId = (Invoke-ImperionDbQuery -Connection $Connection -Sql @"
INSERT INTO posture_snapshot
    (account_id, trigger, business_review_id, score_model_version, composite_score, grade)
VALUES (@a::uuid, @trigger, @br::uuid, @model, @composite, @grade)
RETURNING id
"@ -Parameters @{
                        a = $account; trigger = $Trigger
                        # [string] defaults to '' — must reach the driver as NULL, not ''::uuid
                        br = ($BusinessReviewId ? $BusinessReviewId : $null)
                        model = $score.ModelVersion; composite = $score.Composite; grade = $score.Grade
                    }).id

                foreach ($pillar in $score.Pillars) {
                    Invoke-ImperionDbNonQuery -Connection $Connection -Sql @"
INSERT INTO posture_snapshot_pillar (snapshot_id, pillar, covered, score, weight, metrics)
VALUES (@s::uuid, @pillar, @covered, @score, @weight, @metrics::jsonb)
"@ -Parameters @{
                        s = "$snapshotId"; pillar = $pillar.Pillar; covered = $pillar.Covered
                        score = $pillar.Score; weight = $pillar.Weight
                        metrics = ($pillar.Metrics | ConvertTo-Json -Compress)
                    } | Out-Null
                }

                $transaction.Commit()
                $snapshotted++
            }
            catch {
                # One bad account never blocks the fleet: roll back its transaction,
                # log, and continue — tomorrow's run retries it (still this quarter).
                $transaction.Rollback()
                $failed++
                Write-ImperionLog -Level Error -Source 'posture' `
                    -Message "Posture snapshot failed for account $account - rolled back." `
                    -Data @{ account = $account; error = $_.Exception.Message }
            }
            finally {
                $transaction.Dispose()
            }
        }

        Write-ImperionLog -Level Metric -Source 'posture' -Message 'Posture snapshot complete.' -Data @{
            trigger     = $Trigger
            accounts    = @($AccountId).Count
            snapshotted = $snapshotted
            skipped     = $skipped
            failed      = $failed
            seconds     = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
        }
    }
    finally { if ($ownConnection) { $Connection.Dispose() } }
}
