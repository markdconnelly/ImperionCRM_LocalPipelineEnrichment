function Set-ImperionAzureResourceGroupToBronze {
    <#
    .SYNOPSIS
        Write flattened Azure resource-group rows into the azure_resource_groups bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6). Takes the flat, fully-enveloped [PSCustomObject]
        rows produced by Get-ImperionAzureResourceGroup and upserts them via
        Invoke-ImperionBronzeUpsert (standard envelope, change-detected: unchanged content
        hashes are not rewritten). The collector deliberately over-collects (CLAUDE.md §5 —
        raw_payload stays lossless), so each row's flat columns are projected to exactly the
        azure_resource_groups column set defined by front-end migration 0038 (name, location,
        subscription_id, provisioning_state, tags) before the upsert; extra collector columns
        (e.g. managed_by) survive in raw_payload only.

        Idempotent/resumable. Pass an open -Connection to share one across a batch; otherwise a
        connection is opened per call and disposed. Requires Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionAzureResourceGroup (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to azure_resource_groups (front-end migration 0038).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionAzureResourceGroup -SubscriptionId $sub | Set-ImperionAzureResourceGroupToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'azure_resource_groups'
    )

    begin {
        # Exact column set of azure_resource_groups (front-end migration 0038): flat columns
        # first, then the standard envelope. Anything else the collector emitted is dropped
        # from the flat projection (it remains queryable in raw_payload).
        $tableColumns = @(
            'name', 'location', 'subscription_id', 'provisioning_state', 'tags',
            'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
        )
        $collected = [System.Collections.Generic.List[object]]::new()
    }
    process {
        foreach ($r in $Row) {
            if ($null -eq $r) { continue }
            $projected = [ordered]@{}
            foreach ($column in $tableColumns) { $projected[$column] = Get-ImperionMember $r $column }
            $collected.Add([pscustomobject]$projected)
        }
    }
    end {
        if ($collected.Count -eq 0) {
            Write-ImperionLog -Source 'azure' -Message "${Table}: 0 rows to write."
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
            Write-ImperionLog -Level Metric -Source 'azure' -Message "$Table written." -Data @{
                table = $Table; scanned = $tally.scanned; inserted = $tally.inserted; updated = $tally.updated; unchanged = $tally.unchanged
            }
            return $tally
        }
        finally { if ($ownsConnection) { $conn.Dispose() } }
    }
}
