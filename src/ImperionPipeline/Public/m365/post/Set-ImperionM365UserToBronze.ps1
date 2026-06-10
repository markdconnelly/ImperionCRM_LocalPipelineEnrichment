function Set-ImperionM365UserToBronze {
    <#
    .SYNOPSIS
        Write flattened M365 (Entra) user rows into the m365_contacts bronze table (ADR-0039 shape).
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6) for a table that uses the per-source ADR-0039 shape
        instead of the standard envelope: m365_contacts (front-end migration 0036) keys on a
        UNIQUE external_ref and stores the raw record in payload_bronze; the silver/gold/match
        columns (contact_id, normalized_silver, summary_gold, …) are filled by the front-end
        merge into the unified contact, not here. So each flat row from Get-ImperionM365User is
        projected down to { external_ref ← external_id, payload_bronze ← raw_payload } and
        upserted on external_ref with -NoChangeDetect (the table has no content_hash column;
        change is resolved at merge time).

        Idempotent/resumable. Pass an open -Connection to share one across a batch; otherwise a
        connection is opened per call and disposed. Requires Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionM365User (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to m365_contacts (front-end migration 0036).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionM365User -TenantId $customerTenantId | Set-ImperionM365UserToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'm365_contacts'
    )

    begin {
        $collected = [System.Collections.Generic.List[object]]::new()
    }
    process {
        foreach ($r in $Row) {
            if ($null -ne $r) {
                $collected.Add([pscustomobject]@{ external_ref = $r.external_id; payload_bronze = $r.raw_payload })
            }
        }
    }
    end {
        if ($collected.Count -eq 0) {
            Write-ImperionLog -Source 'm365' -Message "${Table}: 0 rows to write."
            return [pscustomobject]@{ scanned = 0; inserted = 0; updated = 0; unchanged = 0 }
        }
        if (-not $PSCmdlet.ShouldProcess("$Table ($($collected.Count) rows)", 'bronze upsert')) {
            return [pscustomobject]@{ scanned = $collected.Count; inserted = 0; updated = 0; unchanged = 0 }
        }

        $ownsConnection = $false
        $conn = $Connection
        if (-not $conn) { $conn = New-ImperionDbConnection; $ownsConnection = $true }
        try {
            $tally = Invoke-ImperionBronzeUpsert -Connection $conn -Table $Table -Rows $collected.ToArray() `
                -KeyColumns 'external_ref' -JsonColumns 'payload_bronze' -NoChangeDetect
            Write-ImperionLog -Level Metric -Source 'm365' -Message "$Table written." -Data @{
                table = $Table; scanned = $tally.scanned; inserted = $tally.inserted; updated = $tally.updated; unchanged = $tally.unchanged
            }
            return $tally
        }
        finally { if ($ownsConnection) { $conn.Dispose() } }
    }
}
