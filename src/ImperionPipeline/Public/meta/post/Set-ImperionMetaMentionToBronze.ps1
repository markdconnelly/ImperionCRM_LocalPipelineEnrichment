function Set-ImperionMetaMentionToBronze {
    <#
    .SYNOPSIS
        Write flattened Meta brand-mention rows into the meta_mentions bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6), LP #391 / front-end #1365. Takes the flat rows
        produced by Get-ImperionMetaMention and upserts them into meta_mentions. This table is
        NOT the standard bronze envelope: it is keyed on UNIQUE (platform, mention_id) with a
        `raw` jsonb payload and DB-default id/ingested_at (no content_hash). So the upsert is
        configured with -KeyColumns platform,mention_id -JsonColumns raw -NoChangeDetect — every
        conflicting row is refreshed from source (idempotent replace-from-source, §6), the rows
        carry exactly the meta_mentions column set, and a re-run converges without duplicates.

        Thin adapter over Invoke-ImperionBronzePost (issue #105). Pass an open -Connection to
        share one across a batch. Requires Initialize-ImperionContext.
    .PARAMETER Row
        Flat meta_mentions rows from Get-ImperionMetaMention (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to meta_mentions (front-end #1365).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionMetaMention -PageId $pageId | Set-ImperionMetaMentionToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'meta_mentions'
    )

    begin {
        $collected = [System.Collections.Generic.List[object]]::new()
    }
    process {
        foreach ($r in $Row) { if ($null -ne $r) { $collected.Add($r) } }
    }
    end {
        Invoke-ImperionBronzePost -CallerCmdlet $PSCmdlet -Connection $Connection `
            -Rows $collected.ToArray() -Table $Table -LogSource 'meta' `
            -KeyColumns @('platform', 'mention_id') -JsonColumns @('raw') -NoChangeDetect
    }
}
