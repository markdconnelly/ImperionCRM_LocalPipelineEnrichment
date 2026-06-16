function Invoke-ImperionPostureMerge {
    <#
    .SYNOPSIS
        Bulk-classify every tenant's security-posture policies into posture silver and roll up tenant_posture.
    .DESCRIPTION
        The scheduled-bulk half of frontend ADR-0051's two-tier refresh (this repo's
        ADR-0010): the on-prem twin of the cloud pipeline's account-scoped posture
        refresh (cloud pipeline ADR-0015). Enumerates ALL tenants present in the
        posture bronze/golden tables — unmapped tenants included (ADR-0051: surface,
        never hide) — and, per tenant inside ONE transaction:

          1. replaces its posture_policy rows with the five per-family FULL OUTER
             JOIN classifications (compliant / drift / ungoverned / missing — the
             Get-ImperionPolicyDrift semantics, canonical in silver);
          2. upserts the tenant_posture rollup (latest Secure Score with guarded
             text->numeric casts, classification counts, and open credential
             exposures resolved through account_tenant; unmapped tenants get 0).

        PARITY CONTRACT: the classification CASE below mirrors Get-ImperionPolicyDrift
        and the cloud pipeline's posture-run.ts VERBATIM. If one changes, change all
        three — the Pester test pins this SQL.

        A failing tenant rolls back its own transaction and never blocks the fleet;
        the run is idempotent (replace-per-merge + upsert), so a re-run converges.
        Requires Initialize-ImperionContext.
    .PARAMETER TenantId
        Optional tenant subset; default enumerates every tenant observed in posture
        bronze or golden tables.
    .PARAMETER Connection
        Optional open Npgsql connection to reuse; otherwise one is opened and disposed.
    .EXAMPLE
        Invoke-ImperionPostureMerge
    .EXAMPLE
        Invoke-ImperionPostureMerge -TenantId '11111111-2222-3333-4444-555555555555'
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string[]] $TenantId,
        $Connection
    )

    $started = Get-Date
    $ownConnection = -not $Connection
    if ($ownConnection) { $Connection = New-ImperionDbConnection }

    try {
        # Silver-eligible families only: posture_policy.policy_family carries a front-end-owned
        # CHECK constraint, so a family not in it (e.g. purview-compliance, ADR-0019 §2 — held out
        # until the FE widens the constraint) must never reach the silver write. Bronze+golden+drift
        # still cover every family via Get-ImperionPolicyDrift; this merge is silver only.
        $catalog = @(Get-ImperionPolicyCatalog | Where-Object { $_.Silver })

        if (-not $TenantId) {
            # Every tenant the posture estate knows about: observed bronze, golden
            # baselines, and Secure Score snapshots. Unmapped tenants stay in scope.
            $tenantUnionParts = [System.Collections.Generic.List[string]]::new()
            foreach ($p in $catalog) {
                $tenantUnionParts.Add("SELECT tenant_id FROM `"$($p.Observed)`"")
                $tenantUnionParts.Add("SELECT tenant_id FROM `"$($p.Golden)`"")
            }
            $tenantUnionParts.Add('SELECT tenant_id FROM secure_scores')
            $tenantSql = "SELECT DISTINCT tenant_id FROM (`n" +
                ($tenantUnionParts -join "`nUNION ALL ") +
                "`n) t WHERE tenant_id IS NOT NULL ORDER BY tenant_id"
            $TenantId = @(Invoke-ImperionDbQuery -Connection $Connection -Sql $tenantSql |
                    Select-Object -ExpandProperty tenant_id)
        }

        if (@($TenantId).Count -eq 0) {
            Write-ImperionLog -Source 'posture' -Message 'Posture merge: no tenants found in posture bronze/golden.'
            return
        }

        $tenantsMerged = 0
        $tenantsFailed = 0
        $policiesClassified = 0

        foreach ($tenant in $TenantId) {
            if (-not $PSCmdlet.ShouldProcess($tenant, 'Re-classify posture silver')) { continue }

            $transaction = $Connection.BeginTransaction()
            try {
                # posture_policy is CURRENT STATE: replace inside the transaction so
                # readers never see a partial mix of old and new classifications.
                Invoke-ImperionDbNonQuery -Connection $Connection `
                    -Sql 'DELETE FROM posture_policy WHERE tenant_id = @t' `
                    -Parameters @{ t = $tenant } | Out-Null

                foreach ($p in $catalog) {
                    # Table names come from the fixed Get-ImperionPolicyCatalog
                    # allowlist — never from input. The CASE is the parity-pinned
                    # classification (Get-ImperionPolicyDrift / cloud posture-run.ts).
                    $family = $p.Key -replace '-', '_'
                    $insertSql = @"
INSERT INTO posture_policy
    (tenant_id, policy_family, policy_id, policy_name, classification,
     observed_hash, golden_hash, observed_modified_at, golden_approved_at)
SELECT @t, @f,
       COALESCE(o.external_id, g.policy_id),
       COALESCE(o.policy_name, g.policy_name),
       CASE
           WHEN g.policy_id   IS NULL THEN 'ungoverned'
           WHEN o.external_id IS NULL THEN 'missing'
           WHEN o.content_hash = g.golden_hash THEN 'compliant'
           ELSE 'drift'
       END,
       o.content_hash, g.golden_hash,
       CASE WHEN o.modified_date_time ~ '^\d{4}-\d{2}-\d{2}'
            THEN o.modified_date_time::timestamptz END,
       g.approved_at
  FROM "$($p.Observed)" o
  FULL OUTER JOIN "$($p.Golden)" g
    ON g.tenant_id = o.tenant_id AND g.policy_id = o.external_id
 WHERE COALESCE(o.tenant_id, g.tenant_id) = @t
"@
                    $policiesClassified += Invoke-ImperionDbNonQuery -Connection $Connection `
                        -Sql $insertSql -Parameters @{ t = $tenant; f = $family }
                }

                # Rollup: latest Secure Score snapshot (bronze is all-text — numeric
                # casts are regex-guarded so junk lands NULL, never throws), the
                # classification counts just written, and open exposures resolved
                # through account_tenant (an unmapped tenant rolls up 0).
                $rollupSql = @"
WITH latest_score AS (
    SELECT current_score, max_score, licensed_user_count, active_user_count
      FROM secure_scores WHERE tenant_id = @t
     ORDER BY collected_at DESC LIMIT 1
), classification_counts AS (
    SELECT count(*) FILTER (WHERE classification = 'compliant')  AS compliant,
           count(*) FILTER (WHERE classification = 'drift')      AS drift,
           count(*) FILTER (WHERE classification = 'ungoverned') AS ungoverned,
           count(*) FILTER (WHERE classification = 'missing')    AS missing
      FROM posture_policy WHERE tenant_id = @t
), open_exposures AS (
    SELECT count(*) AS n
      FROM credential_exposure e
      JOIN account_tenant m ON m.account_id = e.account_id
     WHERE m.tenant_id = @t AND e.status <> 'resolved'
)
INSERT INTO tenant_posture
    (tenant_id, secure_score_current, secure_score_max, licensed_user_count,
     active_user_count, policies_compliant, policies_drift, policies_ungoverned,
     policies_missing, exposures_open, refreshed_at)
SELECT @t,
       CASE WHEN s.current_score        ~ '^-?\d+(\.\d+)?$' THEN s.current_score::numeric END,
       CASE WHEN s.max_score            ~ '^-?\d+(\.\d+)?$' THEN s.max_score::numeric END,
       CASE WHEN s.licensed_user_count  ~ '^\d+$' THEN s.licensed_user_count::integer END,
       CASE WHEN s.active_user_count    ~ '^\d+$' THEN s.active_user_count::integer END,
       COALESCE(c.compliant, 0), COALESCE(c.drift, 0),
       COALESCE(c.ungoverned, 0), COALESCE(c.missing, 0),
       COALESCE(x.n, 0), now()
  FROM (SELECT 1) AS one
  LEFT JOIN latest_score s ON true
  LEFT JOIN classification_counts c ON true
  LEFT JOIN open_exposures x ON true
ON CONFLICT (tenant_id) DO UPDATE SET
    secure_score_current = EXCLUDED.secure_score_current,
    secure_score_max     = EXCLUDED.secure_score_max,
    licensed_user_count  = EXCLUDED.licensed_user_count,
    active_user_count    = EXCLUDED.active_user_count,
    policies_compliant   = EXCLUDED.policies_compliant,
    policies_drift       = EXCLUDED.policies_drift,
    policies_ungoverned  = EXCLUDED.policies_ungoverned,
    policies_missing     = EXCLUDED.policies_missing,
    exposures_open       = EXCLUDED.exposures_open,
    refreshed_at         = now()
"@
                Invoke-ImperionDbNonQuery -Connection $Connection -Sql $rollupSql `
                    -Parameters @{ t = $tenant } | Out-Null

                $transaction.Commit()
                $tenantsMerged++
            }
            catch {
                # One bad tenant never blocks the fleet: roll back its transaction,
                # log, and continue — the next scheduled run retries it.
                $transaction.Rollback()
                $tenantsFailed++
                Write-ImperionLog -Level Error -Source 'posture' `
                    -Message "Posture merge failed for tenant $tenant - rolled back." `
                    -Data @{ tenant = $tenant; error = $_.Exception.Message }
            }
            finally {
                $transaction.Dispose()
            }
        }

        Write-ImperionLog -Level Metric -Source 'posture' -Message 'Posture merge complete.' -Data @{
            tenants  = @($TenantId).Count
            merged   = $tenantsMerged
            failed   = $tenantsFailed
            policies = $policiesClassified
            seconds  = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
        }
    }
    finally { if ($ownConnection) { $Connection.Dispose() } }
}
