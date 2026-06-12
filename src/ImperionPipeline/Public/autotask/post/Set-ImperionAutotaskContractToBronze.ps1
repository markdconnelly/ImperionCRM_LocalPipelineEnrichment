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

        Thin adapter over Invoke-ImperionBronzePost, the shared post-writer scaffold (issue
        #105) — it owns the gate/connection/upsert/log/tally; this declares table + shape.
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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
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
        Invoke-ImperionBronzePost -CallerCmdlet $PSCmdlet -Connection $Connection `
            -Rows $collected.ToArray() -Table $Table -LogSource 'autotask'
    }
}
