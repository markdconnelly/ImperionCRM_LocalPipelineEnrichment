function Set-ImperionDnsGoldenState {
    <#
    .SYNOPSIS
        Promote a domain's current captured DNS records to its approved DNS Golden State.
    .DESCRIPTION
        The human-gated baseline-approval half of DNS posture (ADR-0063 decision 2, local
        ADR-0008 golden/drift, mirrors Set-ImperionPolicyGoldenState). Captures the domain's
        current ground-truth (public-plane) dns_records into dns_golden as the approved
        per-domain baseline: golden_records is the jsonb set of {record_type, name, value,
        ttl, content_hash} the domain resolves to right now, and golden_hash is a single
        stable hash over that set (so a rollup can compare the whole-domain shape cheaply).
        After approval, Get-ImperionDnsDrift / Invoke-ImperionDnsMerge classify each
        subsequent capture as compliant / drift / ungoverned / missing against this baseline.

        Records are keyed per (tenant_id, domain). account_id is resolved from the
        GUI-managed account_domain registry (migration 0081 / ADR-0063 amendment #334) and
        stamped on the golden row so the silver reads key on it. The public plane is the
        baseline because it is the only plane every domain has (Azure-DNS or not) and is
        what the world actually sees — exactly what drift on SPF/DKIM/DMARC/MX must measure.

        This is a human posture decision — surface it before running broadly (CLAUDE.md §8).
        Idempotent: re-approving a domain overwrites its baseline (ON CONFLICT). Approve one
        domain by name, or every domain in account_domain with -All.

        SCHEMA GATE: until front-end migration 0080/0081 is applied to prod the write fails
        loudly — by design (the caller's catch logs and exits cleanly). Requires
        Initialize-ImperionContext.
    .PARAMETER Domain
        The domain to baseline (its current public-plane records become the golden set).
    .PARAMETER All
        Baseline every domain present in account_domain.
    .PARAMETER Plane
        Which capture plane to freeze as the baseline. Default 'public' (ground-truth, the
        only plane non-Azure domains have); 'azure' freezes the authoritative zone config.
    .PARAMETER ApprovedBy
        Who approved this baseline (recorded for audit).
    .PARAMETER TenantId
        Tenant context for the row key; defaults to the partner tenant. For public-plane rows
        this carries the account id (the resolver stamps account context as tenant_id, #156).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse; otherwise one is opened and disposed.
    .EXAMPLE
        Set-ImperionDnsGoldenState -Domain 'contoso.com' -ApprovedBy 'mark'
    .EXAMPLE
        Set-ImperionDnsGoldenState -All -ApprovedBy 'mark'
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Single')]
    [OutputType([int])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Single')][string] $Domain,
        [Parameter(Mandatory, ParameterSetName = 'All')][switch] $All,
        [ValidateSet('public', 'azure')][string] $Plane = 'public',
        [Parameter(Mandatory)][string] $ApprovedBy,
        [string] $TenantId,
        $Connection
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.LocalTenantId }
    $ownConnection = -not $Connection
    if ($ownConnection) { $Connection = New-ImperionDbConnection }

    try {
        # The whole-domain baseline: freeze the current dns_records for the plane into
        # dns_golden as one row per domain. golden_records is the ordered jsonb set of the
        # records (with each record's content_hash, so a record-level drift join is exact);
        # golden_hash is md5 over the deterministic concatenation of those record hashes, so
        # the rollup can answer "did this domain's shape change at all?" in one comparison.
        # account_id is carried from account_domain (the GUI-managed source of truth).
        $domainFilter = if ($All) { '' } else { 'AND r.domain = @domain' }
        $sql = @"
INSERT INTO dns_golden (tenant_id, domain, account_id, golden_hash, golden_records, golden_approved_by, golden_approved_at)
SELECT r.tenant_id,
       r.domain,
       COALESCE(max(r.account_id), max(ad.account_id)) AS account_id,
       md5(string_agg(r.content_hash, '|' ORDER BY r.external_id)) AS golden_hash,
       jsonb_agg(
           jsonb_build_object(
               'external_id',  r.external_id,
               'record_type',  r.record_type,
               'name',         r.name,
               'value',        r.value,
               'ttl',          r.ttl,
               'content_hash', r.content_hash)
           ORDER BY r.external_id) AS golden_records,
       @by, now()
  FROM dns_records r
  LEFT JOIN account_domain ad ON ad.domain = r.domain
 WHERE r.tenant_id = @t AND r.plane = @plane $domainFilter
 GROUP BY r.tenant_id, r.domain
ON CONFLICT (tenant_id, domain) DO UPDATE SET
    account_id         = EXCLUDED.account_id,
    golden_hash        = EXCLUDED.golden_hash,
    golden_records     = EXCLUDED.golden_records,
    golden_approved_by = EXCLUDED.golden_approved_by,
    golden_approved_at = now()
"@
        $params = @{ by = $ApprovedBy; t = $TenantId; plane = $Plane }
        if (-not $All) { $params.domain = $Domain }

        $target = if ($All) { "all $Plane-plane domains" } else { "$Domain ($Plane plane)" }
        if ($PSCmdlet.ShouldProcess($target, 'Set DNS golden state')) {
            $affected = Invoke-ImperionDbNonQuery -Connection $Connection -Sql $sql -Parameters $params
            Write-ImperionLog -Level Metric -Source 'dns' -Message "DNS golden state set for $target." -Data @{
                plane = $Plane; approved_by = $ApprovedBy; domains = $affected
            }
            return $affected
        }
    }
    finally { if ($ownConnection) { $Connection.Dispose() } }
}
