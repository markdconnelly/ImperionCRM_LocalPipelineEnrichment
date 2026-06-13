function Set-ImperionDnsRecordToBronze {
    <#
    .SYNOPSIS
        Write flattened public-plane DNS records into the dns_records bronze table.
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6) for the public ground-truth plane of DNS posture
        (front-end migration 0080 + 0081 / ADR-0063). Takes the flat, fully-enveloped rows
        from Get-ImperionDnsResolveObject and upserts them via Invoke-ImperionBronzePost
        (standard envelope, PK (tenant_id, source, external_id), change-detected). Each row is
        projected to exactly the dns_records column set — including account_id (the public
        plane is account-scoped, ADR-0063 amendment #334) — so a future collector field can
        never break the insert; anything extra survives in raw_payload.

        Thin adapter over Invoke-ImperionBronzePost (issue #105) — it owns the
        projection/gate/connection/upsert/log/tally; this declares table + column set. The
        azure-plane records share this table but are written by the multi-table
        Set-ImperionDnsZoneToBronze (#155); planes never collide (external_id carries the
        plane). Idempotent/resumable. Requires Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionDnsResolveObject (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to dns_records (front-end migration 0080).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionDnsResolveObject -Domain 'contoso.com' -AccountId $id | Set-ImperionDnsRecordToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'dns_records'
    )

    begin {
        # Exact column set of dns_records (front-end migrations 0080 + 0081 account_id):
        # flat columns first, then the standard envelope. Extras drop from the flat
        # projection (they remain queryable in raw_payload).
        $tableColumns = @(
            'domain', 'plane', 'record_type', 'name', 'value', 'ttl', 'account_id',
            'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash'
        )
        $collected = [System.Collections.Generic.List[object]]::new()
    }
    process {
        foreach ($r in $Row) { if ($null -ne $r) { $collected.Add($r) } }
    }
    end {
        Invoke-ImperionBronzePost -CallerCmdlet $PSCmdlet -Connection $Connection `
            -Rows $collected.ToArray() -Table $Table -LogSource 'dns' -ColumnSet $tableColumns
    }
}
