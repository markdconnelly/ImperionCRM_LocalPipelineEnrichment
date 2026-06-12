function Set-ImperionAutotaskTicketToBronze {
    <#
    .SYNOPSIS
        Write flattened Autotask ticket rows into the autotask_tickets bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6); standard-envelope sibling of
        Set-ImperionAutotaskContractToBronze. Takes the flat rows from
        Get-ImperionAutotaskTicket and change-detected-upserts them via
        Invoke-ImperionBronzeUpsert. Bulk reconcile path — the cloud Pipeline handles
        real-time ticket webhooks (CLAUDE.md §1); this is the scheduled catch-up.

        Thin adapter over Invoke-ImperionBronzePost, the shared post-writer scaffold (issue
        #105) — it owns the gate/connection/upsert/log/tally; this declares table + shape.
        Idempotent/resumable. Pass an open -Connection to share one across a batch; otherwise
        a connection is opened per call and disposed. Requires Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionAutotaskTicket (from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to autotask_tickets (front-end migration 0038).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionAutotaskTicket -SinceDays 1 | Set-ImperionAutotaskTicketToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'autotask_tickets'
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
