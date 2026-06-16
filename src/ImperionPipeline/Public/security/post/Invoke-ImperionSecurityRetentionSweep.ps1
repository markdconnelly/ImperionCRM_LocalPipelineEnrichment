function Invoke-ImperionSecurityRetentionSweep {
    <#
    .SYNOPSIS
        Cap the Microsoft security-incident bronze rows at 180 days, gated + logged, security tables ONLY.
    .DESCRIPTION
        The scheduled on-prem retention enforcer for the security-incident domain (issue #196,
        ADR-0019 §3). Microsoft ages incidents out and AUTOTASK is the durable system of record for
        incident history (ADR-0019 §1); the shared DB therefore only needs a recent operational
        window of high-fidelity Microsoft detail. This cmdlet prunes that window to 180 days.

        SCOPE IS EXACTLY THREE TABLES — m365_incidents, m365_alerts, m365_evidence — and NOTHING
        ELSE. It does NOT touch interaction bronze, does NOT touch the Purview posture tables
        (purview_compliance_*), and is NOT a system-wide sweep (ADR-0019 §3). The prune is
        parent→child aware and runs leaf-first so foreign-key children are removed before their
        parents: evidence (FK alert_id) → alerts (FK incident_id) → incidents. Aged alerts/evidence
        are pruned by their own age AND when their parent is past retention, so a deleted incident
        never strands orphaned children.

        WHY 180 DAYS IS SAFE: Autotask holds the durable incident history (ADR-0019 §1, system of
        record). Deleting an aged Microsoft row never loses the incident — the Autotask ticket
        persists. Bounding the DB to a 180-day window also SHRINKS the standing PII/exposure surface
        (evidence rows can carry hostnames / user identifiers / IPs) — the retention bound is itself
        a security control (ADR-0019 Security impact).

        Follows the ADR-0015 retention idiom (mirrors Invoke-ImperionReceiptLifecycle):
        [CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')], -WhatIf-aware end to end (a dry
        run reports the eligible counts without deleting a single row), COUNT-ONLY structured logging
        (rows scanned / pruned per table — NEVER any row content, no PII, CLAUDE.md §8), idempotent
        and resumable (a re-run converges — already-pruned rows are simply absent). Like every write
        path the deletes are gated; surface before the first live run (CLAUDE.md §8). Requires
        Initialize-ImperionContext.

        AGE COLUMN: prunes by `collected_at` — the ingestion timestamp present on every bronze row
        (the source-supplied created_at can be null/absent). Override with -AgeColumn once the
        operational choice is confirmed live (ADR-0019 §3 notes the exact column is confirmed in the
        collector phase). -TenantId scopes the sweep to one tenant; omit to sweep all.
    .PARAMETER RetentionDays
        Age threshold in days. Rows older than this (by -AgeColumn) are pruned. Default 180 (ADR-0019).
    .PARAMETER AgeColumn
        Timestamp column the age cutoff compares against. Default 'collected_at' (always present).
    .PARAMETER TenantId
        Optional tenant scope; omit to sweep every tenant (per-tenant isolation preserved either way).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse; otherwise one is opened from config and disposed.
    .OUTPUTS
        [pscustomobject] tally { evidence; alerts; incidents } of rows pruned per table.
    .EXAMPLE
        Invoke-ImperionSecurityRetentionSweep
        Prune m365_incidents/alerts/evidence older than 180 days.
    .EXAMPLE
        Invoke-ImperionSecurityRetentionSweep -WhatIf
        Report what would be pruned per table without deleting a single row (dry run).
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [ValidateRange(1, 3650)][int] $RetentionDays = 180,
        [ValidateSet('collected_at', 'created_at')][string] $AgeColumn = 'collected_at',
        [string] $TenantId,
        $Connection
    )

    $started = Get-Date
    $ownConnection = -not $Connection
    if ($ownConnection) { $Connection = New-ImperionDbConnection }

    # Leaf-first so FK children go before parents; the security tables ONLY (ADR-0019 §3).
    # Each table is pruned by its OWN age, so this never reaches outside the three security tables.
    # The age column is validated to an allow-list above (no SQL injection via identifier).
    $tableOrder = @('m365_evidence', 'm365_alerts', 'm365_incidents')

    try {
        $tenantClause = if ($TenantId) { ' AND tenant_id = @t' } else { '' }
        $tally = [ordered]@{ evidence = 0; alerts = 0; incidents = 0 }
        $keyByTable = @{ m365_evidence = 'evidence'; m365_alerts = 'alerts'; m365_incidents = 'incidents' }

        foreach ($table in $tableOrder) {
            $params = @{ days = $RetentionDays }
            if ($TenantId) { $params.t = $TenantId }

            # Count first (count-only logging, and so a -WhatIf dry run reports without deleting).
            $countSql = "SELECT count(*) AS n FROM ""$table"" WHERE ""$AgeColumn"" < (now() - make_interval(days => @days))$tenantClause"
            $countRow = Invoke-ImperionDbQuery -Connection $Connection -Sql $countSql -Parameters $params
            $eligible = [int]($countRow | Select-Object -First 1 -ExpandProperty n)

            if ($eligible -eq 0) {
                Write-ImperionLog -Source 'm365' -Message "${table}: 0 rows past $RetentionDays-day retention."
                continue
            }

            $target = "$table ($eligible rows past $RetentionDays days)"
            if (-not $PSCmdlet.ShouldProcess($target, "Prune security rows older than $RetentionDays days")) {
                Write-ImperionLog -Source 'm365' -Message "${table}: $eligible row(s) eligible for prune (dry run — not deleted)." -Data @{ table = $table; eligible = $eligible; retentionDays = $RetentionDays }
                continue
            }

            $deleteSql = "DELETE FROM ""$table"" WHERE ""$AgeColumn"" < (now() - make_interval(days => @days))$tenantClause"
            $deleted = [int](Invoke-ImperionDbNonQuery -Connection $Connection -Sql $deleteSql -Parameters $params)
            $tally[$keyByTable[$table]] = $deleted
            Write-ImperionLog -Level Metric -Source 'm365' -Message "${table}: pruned $deleted row(s) past $RetentionDays-day retention." -Data @{
                table = $table; pruned = $deleted; retentionDays = $RetentionDays
            }
        }

        $result = [pscustomobject]$tally
        Write-ImperionLog -Level Metric -Source 'm365' -Message 'Security 180-day retention sweep complete.' -Data @{
            evidence = $result.evidence; alerts = $result.alerts; incidents = $result.incidents
            retentionDays = $RetentionDays; ageColumn = $AgeColumn; seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
        }
        return $result
    }
    finally { if ($ownConnection) { $Connection.Dispose() } }
}
