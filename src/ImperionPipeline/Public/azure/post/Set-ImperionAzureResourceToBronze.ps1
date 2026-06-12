function Set-ImperionAzureResourceToBronze {
    <#
    .SYNOPSIS
        Write flattened Azure resource rows into the azure_resources bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6). Takes the flat, fully-enveloped [PSCustomObject]
        rows produced by Get-ImperionAzureResource and upserts them via
        Invoke-ImperionBronzeUpsert (standard envelope, change-detected: unchanged content
        hashes are not rewritten). Each row's flat columns are projected to exactly the
        azure_resources column set defined by front-end migration 0038 (name, type, location,
        resource_group, subscription_id, sku, kind, tags) before the upsert, so a future
        collector field can never break the insert; anything extra survives in raw_payload.

        Thin adapter over Invoke-ImperionBronzePost, the shared post-writer scaffold (issue
        #105) — it owns the projection/gate/connection/upsert/log/tally; this declares
        table + column set.
        Idempotent/resumable. Pass an open -Connection to share one across a batch; otherwise a
        connection is opened per call and disposed. Requires Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionAzureResource (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to azure_resources (front-end migration 0038).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionAzureResource -SubscriptionId $sub | Set-ImperionAzureResourceToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'azure_resources'
    )

    begin {
        # Exact column set of azure_resources (front-end migration 0038): flat columns first,
        # then the standard envelope. Anything else the collector emitted is dropped from the
        # flat projection (it remains queryable in raw_payload).
        $tableColumns = @(
            'name', 'type', 'location', 'resource_group', 'subscription_id', 'sku', 'kind', 'tags',
            'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
        )
        $collected = [System.Collections.Generic.List[object]]::new()
    }
    process {
        foreach ($r in $Row) { if ($null -ne $r) { $collected.Add($r) } }
    }
    end {
        Invoke-ImperionBronzePost -CallerCmdlet $PSCmdlet -Connection $Connection `
            -Rows $collected.ToArray() -Table $Table -LogSource 'azure' -ColumnSet $tableColumns
    }
}
