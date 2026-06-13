function Set-ImperionSharePointSiteToBronze {
    <#
    .SYNOPSIS
        Write flattened SharePoint site inventory rows into the sharepoint_sites bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6) for the SharePoint site inventory (issue #137;
        front-end migration 0078 / issue #255): sharepoint_sites — standard envelope, PK
        (tenant_id, source, external_id) where external_id = the Graph composite site id,
        change-detected (unchanged content hashes are not rewritten).

        Rows are projected to exactly the migration-0078 column set
        (Invoke-ImperionBronzePost -ColumnSet): missing columns land NULL, any future
        collector field is dropped from the flat projection but survives in raw_payload,
        so the insert can never break on collector drift. The table is site METADATA
        only by design — 0078 has no file/drive/item columns and none may ever be added
        (Files.Read.All pruned, Mark's 2026-06-12 verdict).

        SCHEMA GATE: until migration 0078 is applied to prod, the upsert fails loudly —
        by design (the task file's catch logs + exits cleanly; this repo never creates
        tables, CLAUDE.md §6).

        Thin adapter over Invoke-ImperionBronzePost (issue #105 scaffold). Idempotent/
        resumable. Pass an open -Connection to share one across a batch.
        Requires Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionSharePointSite (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to sharepoint_sites (front-end migration 0078).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionSharePointSite | Set-ImperionSharePointSiteToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'sharepoint_sites'
    )

    begin {
        # Exact sharepoint_sites column set (front-end migration 0078), then the
        # standard envelope.
        $tableColumns = @(
            'display_name', 'name', 'web_url', 'description',
            'created_date_time', 'last_modified_date_time',
            'web_template', 'is_personal_site', 'site_collection_hostname',
            'storage_used_bytes', 'storage_quota_bytes',
            'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
        )
        $collected = [System.Collections.Generic.List[object]]::new()
    }
    process {
        foreach ($r in $Row) { if ($null -ne $r) { $collected.Add($r) } }
    }
    end {
        Invoke-ImperionBronzePost -CallerCmdlet $PSCmdlet -Connection $Connection `
            -Rows $collected.ToArray() -Table $Table -LogSource 'm365' -ColumnSet $tableColumns
    }
}
