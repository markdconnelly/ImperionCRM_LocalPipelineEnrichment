function Invoke-ImperionDnsMerge {
    <#
    .SYNOPSIS
        Roll every governed domain's DNS drift + governance verdict into the dns_domain silver table.
    .DESCRIPTION
        The scheduled-bulk write half of the DNS silver merge (front-end ADR-0063, local
        ADR-0008; issue #157) — the on-prem twin of the cloud pipeline's account-scoped DNS
        on-demand refresh. Calls Get-ImperionDnsDrift to classify each domain (record-level
        drift counts + the three-state governance verdict, reconciled across the Azure manage
        plane and the public ground-truth plane), then upserts one dns_domain row per domain.

        Idempotent: dns_domain is keyed (tenant_id, domain) and the write is an ON CONFLICT
        upsert, so a re-run converges and never duplicates. Each domain upserts independently
        so a single bad domain never blocks the fleet — it is logged and skipped. Runs daily
        after the two collectors (azure/dns-zones #155, azure/dns-resolve #156). Requires
        Initialize-ImperionContext.

        The classification SQL is OWNED by Get-ImperionDnsDrift and reused verbatim by the
        cloud on-demand refresh — the parity contract (ADR-0063 decision 2): change the
        classification in one place, it changes everywhere. This cmdlet only persists.
    .PARAMETER Domain
        Optional single domain; default merges every domain in account_domain.
    .PARAMETER Connection
        Optional open Npgsql connection to reuse; otherwise one is opened and disposed.
    .EXAMPLE
        Invoke-ImperionDnsMerge
    .EXAMPLE
        Invoke-ImperionDnsMerge -Domain 'contoso.com'
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [string] $Domain,
        $Connection
    )

    $started = Get-Date
    $ownConnection = -not $Connection
    if ($ownConnection) { $Connection = New-ImperionDbConnection }

    try {
        $rows = Get-ImperionDnsDrift -Connection $Connection -Domain $Domain
        if (-not $rows -or @($rows).Count -eq 0) {
            Write-ImperionLog -Source 'dns' -Message 'DNS merge: no governed domains found in account_domain.'
            return [pscustomobject]@{ domains = 0; merged = 0; failed = 0 }
        }

        # account_domain is account-keyed; dns_domain is keyed (tenant_id, domain). The
        # public-plane rows carry the account id as tenant_id (the isolation owner, #156),
        # so tenant_id := account_id keeps the silver read account-scoped and consistent
        # with how the collectors stamped the bronze.
        $upsertSql = @"
INSERT INTO dns_domain
    (tenant_id, domain, account_id, verdict, records_compliant, records_drift,
     records_ungoverned, records_missing, score, last_captured_at, refreshed_at)
VALUES
    (@tenant, @domain, @account, @verdict, @compliant, @drift,
     @ungoverned, @missing, @score, @captured, now())
ON CONFLICT (tenant_id, domain) DO UPDATE SET
    account_id         = EXCLUDED.account_id,
    verdict            = EXCLUDED.verdict,
    records_compliant  = EXCLUDED.records_compliant,
    records_drift      = EXCLUDED.records_drift,
    records_ungoverned = EXCLUDED.records_ungoverned,
    records_missing    = EXCLUDED.records_missing,
    score              = EXCLUDED.score,
    last_captured_at   = EXCLUDED.last_captured_at,
    refreshed_at       = now()
"@

        $merged = 0
        $failed = 0
        foreach ($r in $rows) {
            if (-not $PSCmdlet.ShouldProcess($r.domain, "Merge DNS silver ($($r.verdict))")) { continue }
            $accountId = if ($r.account_id) { [string]$r.account_id } else { $null }
            $params = @{
                tenant     = if ($accountId) { $accountId } else { $r.domain }
                domain     = $r.domain
                account    = $accountId
                verdict    = $r.verdict
                compliant  = [int]$r.records_compliant
                drift      = [int]$r.records_drift
                ungoverned = [int]$r.records_ungoverned
                missing    = [int]$r.records_missing
                score      = $r.score
                captured   = $r.last_captured_at
            }
            try {
                Invoke-ImperionDbNonQuery -Connection $Connection -Sql $upsertSql -Parameters $params | Out-Null
                $merged++
            }
            catch {
                # One bad domain never blocks the fleet: log and continue; the next run retries.
                $failed++
                Write-ImperionLog -Level Error -Source 'dns' `
                    -Message "DNS merge failed for domain $($r.domain) - skipped." `
                    -Data @{ domain = $r.domain; error = $_.Exception.Message }
            }
        }

        Write-ImperionLog -Level Metric -Source 'dns' -Message 'DNS merge complete.' -Data @{
            domains = @($rows).Count
            merged  = $merged
            failed  = $failed
            seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
        }
        return [pscustomobject]@{ domains = @($rows).Count; merged = $merged; failed = $failed }
    }
    finally { if ($ownConnection) { $Connection.Dispose() } }
}
