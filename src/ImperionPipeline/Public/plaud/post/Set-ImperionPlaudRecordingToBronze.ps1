function Set-ImperionPlaudRecordingToBronze {
    <#
    .SYNOPSIS
        Write flattened Plaud recording rows into the plaud_recordings bronze table (PENDING front-end migration).
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6). Takes the flat, fully-enveloped [PSCustomObject]
        rows produced by Get-ImperionPlaudRecording and upserts them (standard envelope,
        change-detected). Each row is projected to exactly the PROPOSED plaud_recordings
        column set (title, started_at, duration_seconds, summary, action_items,
        transcript) before the upsert; extras survive in raw_payload.

        SCHEMA GATE (issue #72): the `plaud_recordings` table does NOT exist yet — it
        needs a front-end migration via the schema-handoff process (proposed DDL in
        docs/integrations/plaud.md; this repo NEVER creates tables, CLAUDE.md §6). Until
        it lands and the SP is granted write, this writer fails loudly at the upsert —
        by design. The bronze→silver `meeting` feed (plaud_summary / transcript_ref,
        1:1 interaction(kind=meeting)) is the follow-up merge, tracked on #72.

        Thin adapter over Invoke-ImperionBronzePost (issue #105 scaffold). Idempotent/
        resumable. Pass an open -Connection to share one across a batch; otherwise a
        connection is opened per call and disposed. Requires Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionPlaudRecording (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to plaud_recordings (front-end migration pending).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionPlaudRecording | Set-ImperionPlaudRecordingToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'plaud_recordings'
    )

    begin {
        # PROPOSED plaud_recordings column set (front-end migration pending — issue #72
        # schema handoff): flat columns first, then the standard envelope.
        $tableColumns = @(
            'title', 'started_at', 'duration_seconds', 'summary', 'action_items', 'transcript',
            'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
        )
        $collected = [System.Collections.Generic.List[object]]::new()
    }
    process {
        foreach ($r in $Row) { if ($null -ne $r) { $collected.Add($r) } }
    }
    end {
        Invoke-ImperionBronzePost -CallerCmdlet $PSCmdlet -Connection $Connection `
            -Rows $collected.ToArray() -Table $Table -LogSource 'plaud' -ColumnSet $tableColumns
    }
}
