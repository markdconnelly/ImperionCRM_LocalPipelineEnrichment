function Get-ImperionDnsDrift {
    <#
    .SYNOPSIS
        Classify each domain's current DNS capture against its approved Golden State and compute its governance verdict.
    .DESCRIPTION
        The read half of the DNS silver merge (front-end ADR-0063, local ADR-0008 golden/drift;
        issue #157). For every domain in the account_domain registry (or one via -Domain) it
        answers two questions per ADR-0063:

          1. DRIFT — record-level classification of the current public-plane capture
             (dns_records, plane='public') against the human-approved baseline
             (dns_golden.golden_records). Each record full-outer-joins captured-vs-golden on
             (record_type, name) and is classified with the SAME four-state semantics as
             Get-ImperionPolicyDrift (ADR-0051 §3 / ADR-0008):
               compliant  — captured content_hash matches the golden record's content_hash
               drift      — captured differs from the approved record
               ungoverned — captured exists, no golden baseline approved yet (whole domain or record)
               missing    — golden record approved, but the capture no longer resolves it
             Counts roll up to records_compliant / drift / ungoverned / missing.

          2. VERDICT — the three-state governance ladder (ADR-0063 decision 3), reconciled
             ACROSS the two planes:
               not-in-azure      — no dns_zones row (the domain is not hosted in Azure DNS)
               in-azure-readonly — an Azure zone exists but the SP holds no write role,
                                   OR it is manageable but the live public NS do not delegate
                                   to the Azure zone (visible, not authoritative)
               managed           — in Azure AND write proven AND the live public NS resolve to
                                   the Azure zone's nameservers (hosted in Azure and manageable)
             The NS-delegation check is the cross-plane reconciliation: the public NS records
             (dns_records plane='public', record_type='NS') must intersect the Azure zone's
             ns_records. Only then is the domain authoritative-in-Azure.

        Read-only — returns one PSCustomObject per domain (verdict, the four counts, score,
        last_captured_at). Invoke-ImperionDnsMerge persists these to dns_domain; the cloud
        on-demand refresh reuses this same classification. Pass -Connection to reuse an open
        connection; otherwise one is opened and disposed. Requires Initialize-ImperionContext.

        SCORE: 0–100, drift- and verdict-weighted. Governed records that are compliant earn
        full marks; drift and missing are penalised; a non-managed verdict caps the ceiling.
        Computed in SQL so the cloud twin produces the identical number.
    .PARAMETER Domain
        Optional single domain; default classifies every domain in account_domain.
    .PARAMETER Connection
        Optional open Npgsql connection to reuse.
    .EXAMPLE
        Get-ImperionDnsDrift | Where-Object verdict -ne 'managed'
    .EXAMPLE
        Get-ImperionDnsDrift -Domain 'contoso.com'
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [string] $Domain,
        $Connection
    )

    $ownConnection = -not $Connection
    if ($ownConnection) { $Connection = New-ImperionDbConnection }

    try {
        # One set-based pass over every governed domain. The two planes are reconciled here:
        #   golden_record   — the approved baseline records, unnested from dns_golden.golden_records
        #   captured_record — the current public-plane dns_records
        #   azure_zone      — the manage-plane dns_zones row (verdict + manageable + ns_records)
        #   public_ns       — the live public NS the domain delegates to (cross-plane signal)
        # Record classification mirrors the policy-drift CASE; the verdict ladder reconciles
        # in_azure / manageable / NS-delegation. account_id is carried for the account-scoped read.
        $domainFilter = if ($Domain) { 'WHERE ad.domain = @domain' } else { '' }
        $sql = @"
WITH governed AS (
    SELECT ad.domain, ad.account_id
      FROM account_domain ad
      $domainFilter
),
golden_record AS (
    SELECT g.domain,
           gr->>'record_type' AS record_type,
           gr->>'name'        AS name,
           gr->>'content_hash' AS content_hash
      FROM dns_golden g
      CROSS JOIN LATERAL jsonb_array_elements(g.golden_records) AS gr
),
captured_record AS (
    SELECT r.domain, r.record_type, r.name, r.content_hash
      FROM dns_records r
     WHERE r.plane = 'public'
),
classified AS (
    SELECT gov.domain,
           CASE
               WHEN g.name IS NULL THEN 'ungoverned'
               WHEN c.name IS NULL THEN 'missing'
               WHEN c.content_hash = g.content_hash THEN 'compliant'
               ELSE 'drift'
           END AS status
      FROM governed gov
      LEFT JOIN golden_record   g ON g.domain = gov.domain
      FULL OUTER JOIN captured_record c
             ON c.domain = COALESCE(g.domain, gov.domain)
            AND c.record_type = g.record_type
            AND c.name = g.name
     WHERE COALESCE(g.domain, c.domain) IN (SELECT domain FROM governed)
),
counts AS (
    SELECT domain,
           count(*) FILTER (WHERE status = 'compliant')  AS records_compliant,
           count(*) FILTER (WHERE status = 'drift')      AS records_drift,
           count(*) FILTER (WHERE status = 'ungoverned') AS records_ungoverned,
           count(*) FILTER (WHERE status = 'missing')    AS records_missing
      FROM classified
     GROUP BY domain
),
public_ns AS (
    -- the nameserver labels the domain currently delegates to (split the resolver's
    -- '; '-joined NS value into individual host labels for intersection with the zone)
    SELECT DISTINCT r.domain, lower(trim(ns)) AS ns_host
      FROM dns_records r
      CROSS JOIN LATERAL regexp_split_to_table(r.value, '\s*;\s*') AS ns
     WHERE r.plane = 'public' AND r.record_type = 'NS' AND trim(ns) <> ''
),
azure_zone AS (
    SELECT z.domain,
           bool_or(z.in_azure = 'true')   AS in_azure,
           bool_or(z.manageable = 'true') AS manageable,
           string_agg(lower(z.ns_records), ' ') AS zone_ns
      FROM dns_zones z
     GROUP BY z.domain
),
ns_delegated AS (
    SELECT pn.domain
      FROM public_ns pn
      JOIN azure_zone az ON az.domain = pn.domain
     WHERE az.zone_ns LIKE '%' || pn.ns_host || '%'
     GROUP BY pn.domain
),
last_capture AS (
    SELECT domain, max(collected_at) AS last_captured_at
      FROM dns_records
     WHERE plane = 'public'
     GROUP BY domain
)
SELECT gov.domain,
       gov.account_id,
       COALESCE(cn.records_compliant, 0)  AS records_compliant,
       COALESCE(cn.records_drift, 0)      AS records_drift,
       COALESCE(cn.records_ungoverned, 0) AS records_ungoverned,
       COALESCE(cn.records_missing, 0)    AS records_missing,
       CASE
           WHEN az.in_azure IS NOT TRUE THEN 'not-in-azure'
           WHEN az.manageable IS TRUE AND nd.domain IS NOT NULL THEN 'managed'
           ELSE 'in-azure-readonly'
       END AS verdict,
       lc.last_captured_at,
       -- score: share of governed records that are compliant (0 when none governed),
       -- scaled to 100, then capped at 60 unless the domain is fully 'managed'.
       CASE
           WHEN COALESCE(cn.records_compliant, 0) + COALESCE(cn.records_drift, 0)
              + COALESCE(cn.records_missing, 0) = 0 THEN NULL
           ELSE LEAST(
               CASE WHEN az.in_azure IS TRUE AND az.manageable IS TRUE AND nd.domain IS NOT NULL
                    THEN 100 ELSE 60 END,
               round(100.0 * COALESCE(cn.records_compliant, 0)
                   / NULLIF(COALESCE(cn.records_compliant, 0) + COALESCE(cn.records_drift, 0)
                          + COALESCE(cn.records_missing, 0), 0)))
       END AS score
  FROM governed gov
  LEFT JOIN counts       cn ON cn.domain = gov.domain
  LEFT JOIN azure_zone   az ON az.domain = gov.domain
  LEFT JOIN ns_delegated nd ON nd.domain = gov.domain
  LEFT JOIN last_capture lc ON lc.domain = gov.domain
 ORDER BY gov.domain
"@
        $params = @{}
        if ($Domain) { $params.domain = $Domain }
        return Invoke-ImperionDbQuery -Connection $Connection -Sql $sql -Parameters $params
    }
    finally { if ($ownConnection) { $Connection.Dispose() } }
}
