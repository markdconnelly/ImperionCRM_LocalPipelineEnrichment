function Invoke-ImperionPax8Merge {
    <#
    .SYNOPSIS
        Resolve every Pax8 customer company to its silver `account` (record the link in the
        entity-resolution registry `entity_xref`, source_system 'pax8') AND project
        `pax8_subscriptions` into silver `license_assignment` through that link (#316) — the
        bronze→silver merge for Pax8, co-located with the LP collector (#279, #280).
    .DESCRIPTION
        ADR-0026 (merge-co-locates-with-ingestion): the local pipeline INGESTS the Pax8 bronze
        (Invoke-ImperionPax8CompanySync/…, #279), so it owns the bronze→silver merge too.

        Pax8 introduces NO new silver entity — it ENRICHES what already exists (front-end
        docs/integrations/pax8-integration.md). The single thing the merge must establish is the
        identity link "this Pax8 company IS this client `account`": once that link exists in the
        golden-record registry (`entity_xref`, #1054), every downstream Pax8 fact
        (pax8_subscriptions / pax8_licenses / pax8_orders, all keyed on `company_id` =
        pax8_company_id) becomes account-resolvable by joining through it. That account-resolved
        license picture is the "actual licensed seat" side of the agreement true-up (#1041) and the
        join spine for the procure→provision→bill loop (#1042).

        Resolution (the acceptance "entity-res registry when available; account_id fallback"):
          - The registry IS `entity_xref`. We DERIVE the link by NORMALIZED EXACT NAME MATCH of the
            Pax8 company name against silver `account.name` (lower(btrim(...))), and WRITE the
            result back into the registry so the next run (and the backend resolver) reads it
            directly.
          - Ambiguity is treated as UNRESOLVED: a Pax8 name that matches zero or MORE THAN ONE
            account is left unmapped (never guess which "Acme" — the exact reason entity_xref
            exists, 0160). Unmapped companies stay in bronze, queryable, and surface as a count.
          - A HUMAN-CURATED mapping wins: the upsert's DO UPDATE is guarded by
            `WHERE entity_xref.match_method <> 'manual'`, so a fuzzy name re-derivation never
            clobbers a manual link.

        Idempotent: upsert on the registry's UNIQUE (entity_type, source_system, source_key) via
        ON CONFLICT, so the merge converges and never duplicates — safe to run every cadence
        immediately after the Pax8 collectors. Each company upserts independently inside its own
        try/catch, so one bad row never blocks the rest (the cloud_asset/posture precedent). The
        local-pipeline role holds SELECT/INSERT/UPDATE on entity_xref (0160) and SELECT on account
        — no DELETE is used (replace-from-source is achieved by the keyed upsert). Requires
        Initialize-ImperionContext.

        0 rows until front-end migration 0161 is applied, the Pax8 credential lands, and the
        collector (#279) has written pax8_companies bronze — all Mark-gated (#1042). The
        subscription/license → `contract` line and license → `device` LINKS need silver columns
        that do not exist yet; they are a front-end schema follow-up (filed against #1042), NOT
        invented here (this repo never owns schema — CLAUDE.md §5/§6).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse; otherwise one is opened and disposed.
    .EXAMPLE
        Invoke-ImperionPax8Merge
    .EXAMPLE
        Invoke-ImperionPax8Merge -WhatIf   # show the plan without touching the registry
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        $Connection
    )

    $started = Get-Date
    if (-not $PSCmdlet.ShouldProcess('pax8_companies bronze', 'resolve to account + record entity_xref (pax8)')) { return }

    $ownConnection = -not $Connection
    if ($ownConnection) { $Connection = New-ImperionDbConnection }

    try {
        # Resolve each DISTINCT Pax8 company to an account by NORMALIZED EXACT NAME match. The
        # LATERAL returns the lone account id and the match count so PowerShell can keep only the
        # unambiguous (count = 1) matches — zero/many is left unmapped (never guess which "Acme").
        $rows = Invoke-ImperionDbQuery -Connection $Connection -Sql @"
SELECT p.pax8_company_id,
       p.name           AS pax8_name,
       m.account_id::text AS account_id,
       m.match_count
  FROM (
        SELECT DISTINCT pax8_company_id, name
          FROM pax8_companies
         WHERE pax8_company_id IS NOT NULL AND btrim(pax8_company_id) <> ''
           AND name IS NOT NULL            AND btrim(name) <> ''
       ) p
  LEFT JOIN LATERAL (
        SELECT min(a.id) AS account_id, count(*) AS match_count
          FROM account a
         WHERE lower(btrim(a.name)) = lower(btrim(p.name))
       ) m ON true
"@

        if (-not $rows -or @($rows).Count -eq 0) {
            Write-ImperionLog -Source 'pax8' -Message 'Pax8 merge: no pax8_companies bronze rows.'
            return [pscustomobject]@{ companies = 0; resolved = 0; unresolved = 0; failed = 0 }
        }

        # Keyed upsert on the registry's UNIQUE (entity_type, source_system, source_key). The
        # DO UPDATE is guarded so a fuzzy name re-derivation never overwrites a manual link.
        $upsertSql = @"
INSERT INTO entity_xref (
    entity_type, internal_entity_id, source_system, source_key, match_confidence, match_method
)
VALUES (
    'account', @internal_entity_id::uuid, 'pax8', @source_key, 0.800, 'fuzzy'
)
ON CONFLICT (entity_type, source_system, source_key) DO UPDATE SET
    internal_entity_id = EXCLUDED.internal_entity_id,
    match_confidence   = EXCLUDED.match_confidence,
    match_method       = EXCLUDED.match_method,
    updated_at         = now()
WHERE entity_xref.match_method <> 'manual'
"@

        $resolved = 0
        $unresolved = 0
        $failed = 0
        foreach ($r in $rows) {
            # Ambiguity guard: only an EXACTLY-ONE name match is a trustworthy link. Zero or many
            # leaves the company unmapped (kept in bronze) — surfaced as the unresolved count.
            $matchCount = [int]$r.match_count
            if ($matchCount -ne 1 -or [string]::IsNullOrWhiteSpace([string]$r.account_id)) {
                $unresolved++
                continue
            }
            if (-not $PSCmdlet.ShouldProcess([string]$r.pax8_company_id, 'Upsert entity_xref (account, pax8)')) { continue }
            $params = @{
                internal_entity_id = [string]$r.account_id
                source_key         = [string]$r.pax8_company_id
            }
            try {
                Invoke-ImperionDbNonQuery -Connection $Connection -Sql $upsertSql -Parameters $params | Out-Null
                $resolved++
            }
            catch {
                # One bad row never blocks the rest: log and continue; the next run retries.
                $failed++
                Write-ImperionLog -Level Error -Source 'pax8' `
                    -Message "Pax8 merge failed for company $($r.pax8_company_id) - skipped." `
                    -Data @{ pax8_company_id = $r.pax8_company_id; error = $_.Exception.Message }
            }
        }

        # ── Populate silver `license_assignment` from pax8_subscriptions (#316, migration 0185) ──
        # Option B (#338): Pax8 exposes NO /v1/licenses endpoint, so the SUBSCRIPTION is the
        # license grain — external_ref = the Pax8 subscription id, quantity = the SUBSCRIBED seat
        # count (the distributor "purchased" side of the #1041 true-up; the per-user ASSIGNED side
        # is a future M365 license collector). Account-resolved by joining the subscription's
        # company_id to the entity_xref link the loop above just wrote. Set-based + idempotent
        # (ON CONFLICT (source, external_ref)); device_id/contract_id stay NULL until the
        # provision/attach links resolve (#1042/#1085). quantity is regex-guarded (bronze stores
        # it as text); one non-numeric value yields NULL, never a failed statement.
        $licenseSql = @"
INSERT INTO license_assignment (
    account_id, source, external_ref, subscription_ref, product_id, product_name,
    quantity, status, collected_at
)
SELECT x.internal_entity_id,
       'pax8',
       s.pax8_subscription_id,
       s.pax8_subscription_id,
       NULLIF(btrim(s.product_id), ''),
       NULLIF(btrim(s.product_name), ''),
       CASE WHEN btrim(s.quantity) ~ '^[0-9]+$' THEN btrim(s.quantity)::int ELSE NULL END,
       NULLIF(btrim(s.status), ''),
       NULLIF(btrim(s.collected_at), '')::timestamptz
  FROM pax8_subscriptions s
  JOIN entity_xref x
    ON x.entity_type = 'account' AND x.source_system = 'pax8' AND x.source_key = s.company_id
 WHERE s.pax8_subscription_id IS NOT NULL AND btrim(s.pax8_subscription_id) <> ''
ON CONFLICT (source, external_ref) DO UPDATE SET
    account_id       = EXCLUDED.account_id,
    subscription_ref = EXCLUDED.subscription_ref,
    product_id       = EXCLUDED.product_id,
    product_name     = EXCLUDED.product_name,
    quantity         = EXCLUDED.quantity,
    status           = EXCLUDED.status,
    collected_at     = EXCLUDED.collected_at,
    updated_at       = now()
"@
        $licenses = 0
        if ($PSCmdlet.ShouldProcess('license_assignment', 'populate from pax8_subscriptions (account-resolved)')) {
            try {
                $affected = Invoke-ImperionDbNonQuery -Connection $Connection -Sql $licenseSql
                if ($affected -is [int]) { $licenses = $affected }
            }
            catch {
                # Non-fatal: the company links still landed; the next run retries the projection.
                Write-ImperionLog -Level Error -Source 'pax8' `
                    -Message 'Pax8 license_assignment populate failed.' -Data @{ error = $_.Exception.Message }
            }
        }

        Write-ImperionLog -Level Metric -Source 'pax8' -Message 'Pax8 merge complete.' -Data @{
            companies  = @($rows).Count
            resolved   = $resolved
            unresolved = $unresolved
            failed     = $failed
            licenses   = $licenses
            seconds    = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
        }
        return [pscustomobject]@{ companies = @($rows).Count; resolved = $resolved; unresolved = $unresolved; failed = $failed; licenses = $licenses }
    }
    finally { if ($ownConnection) { $Connection.Dispose() } }
}
