function Set-ImperionM365TeamsMeetingToBronze {
    <#
    .SYNOPSIS
        Write flattened cross-org Teams meeting rows into the m365_teams_meetings bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6) for the m365 communications path (issue #100;
        front-end migration 0065 / ImperionCRM#182). Takes the flat rows produced by
        Get-ImperionM365TeamsMeeting (source 'm365_teams', cross-org filtered), renames
        the collector's `user` flat column to the table's `user_upn` (0065: `user` is a
        reserved keyword), and upserts with change detection projected to exactly the
        migration-0065 column set; extras survive in raw_payload.

        NOTE: migration 0065 is merged but not yet applied to prod (orchestrator batches
        the apply) — until then the upsert fails loudly and the task's catch gates it.

        Thin adapter over Invoke-ImperionBronzePost (issue #105 scaffold). Idempotent/
        resumable. Pass an open -Connection to share one across a batch. Requires
        Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionM365TeamsMeeting (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to m365_teams_meetings (front-end migration 0065).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionM365TeamsMeeting -User 'ada@imperionllc.com' -ClientDomain 'acme.com' | Set-ImperionM365TeamsMeetingToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'm365_teams_meetings'
    )

    begin {
        # Exact column set of m365_teams_meetings (front-end migration 0065; collector
        # `user` lands in `user_upn`).
        $tableColumns = @(
            'user_upn', 'subject', 'organizer_address', 'attendee_addresses',
            'start_date_time', 'end_date_time', 'is_online_meeting',
            'online_meeting_provider', 'join_url', 'is_cancelled', 'web_link',
            'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
        )
        $collected = [System.Collections.Generic.List[object]]::new()
    }
    process {
        foreach ($r in $Row) {
            if ($null -eq $r) { continue }
            # Rename user -> user_upn for the 0065 table; the original stays in raw_payload.
            $userUpn = Get-ImperionMember $r 'user'
            $r | Add-Member -NotePropertyName 'user_upn' -NotePropertyValue $userUpn -Force
            $collected.Add($r)
        }
    }
    end {
        Invoke-ImperionBronzePost -CallerCmdlet $PSCmdlet -Connection $Connection `
            -Rows $collected.ToArray() -Table $Table -LogSource 'm365' -ColumnSet $tableColumns
    }
}
