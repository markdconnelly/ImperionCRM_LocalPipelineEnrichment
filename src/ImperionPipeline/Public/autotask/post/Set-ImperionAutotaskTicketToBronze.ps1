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
