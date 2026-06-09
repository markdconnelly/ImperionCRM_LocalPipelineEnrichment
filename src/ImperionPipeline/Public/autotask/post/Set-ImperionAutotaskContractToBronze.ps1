function Set-ImperionAutotaskContractToBronze {
    <#
    .SYNOPSIS
        Write flattened Autotask contract rows into the autotask_contracts bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6). Takes the flat, fully-enveloped [PSCustomObject]
        rows produced by Get-ImperionAutotaskContract and upserts them via
        Invoke-ImperionBronzeUpsert (change-detected: unchanged content hashes are not
        rewritten). This is the reference implementation of the get -> post pattern every
        other source copies: get collects + flattens, post opens a short-lived Entra-token DB
        connection (ADR-0003), upserts, and emits a metric log line with the tally.

        Idempotent and resumable (CLAUDE.md §8): re-running converges, never duplicates. Pass
        an open -Connection to share one connection across a batch/backfill; otherwise a
        connection is opened per call and disposed. Requires Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionAutotaskContract (accepted from the pipeline). Rows
        already carry the standard envelope (tenant_id, source, external_id, collected_at,
        raw_payload, content_hash), so no reshaping happens here.
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. When omitted, one is opened from config and
        disposed before returning.
    .PARAMETER Table
        Target bronze table. Defaults to autotask_contracts (front-end migration 0038).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionAutotaskContract -SinceDays 30 | Set-ImperionAutotaskContractToBronze
    .EXAMPLE
        # Backfill reusing one connection:
        $c = New-ImperionDbConnection
        Get-ImperionAutotaskContract | Set-ImperionAutotaskContractToBronze -Connection $c
        $c.Dispose()
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'autotask_contracts'
    )

    begin {
        $collected = [System.Collections.Generic.List[object]]::new()
    }
    process {
        foreach ($r in $Row) { if ($null -ne $r) { $collected.Add($r) } }
    }
    end {
        if ($collected.Count -eq 0) {
            Write-ImperionLog -Source 'autotask' -Message "${Table}: 0 rows to write."
            return [pscustomobject]@{ scanned = 0; inserted = 0; updated = 0; unchanged = 0 }
        }
        if (-not $PSCmdlet.ShouldProcess("$Table ($($collected.Count) rows)", 'bronze upsert')) {
            return [pscustomobject]@{ scanned = $collected.Count; inserted = 0; updated = 0; unchanged = 0 }
        }

        $ownsConnection = $false
        $conn = $Connection
        if (-not $conn) { $conn = New-ImperionDbConnection; $ownsConnection = $true }
        try {
            $tally = Invoke-ImperionBronzeUpsert -Connection $conn -Table $Table -Rows $collected.ToArray()
            Write-ImperionLog -Level Metric -Source 'autotask' -Message "$Table written." -Data @{
                table = $Table; scanned = $tally.scanned; inserted = $tally.inserted; updated = $tally.updated; unchanged = $tally.unchanged
            }
            return $tally
        }
        finally { if ($ownsConnection) { $conn.Dispose() } }
    }
}
