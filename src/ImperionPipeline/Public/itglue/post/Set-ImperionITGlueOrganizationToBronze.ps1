function Set-ImperionITGlueOrganizationToBronze {
    <#
    .SYNOPSIS
        Write flattened IT Glue organization rows into the itglue_companies bronze table (ADR-0039 shape).
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6) for a table that uses the per-source ADR-0039 shape
        instead of the standard envelope: itglue_companies (front-end migration 0036) keys on a
        UNIQUE external_ref and stores the raw record in payload_bronze; the silver/gold/match
        columns (account_id, normalized_silver, summary_gold, …) are filled by the front-end
        merge into the unified account, not here. So each flat row from
        Get-ImperionITGlueOrganization is projected down to { external_ref ← external_id,
        payload_bronze ← raw_payload } and upserted on external_ref with -NoChangeDetect (the
        table has no content_hash column; change is resolved at merge time).

        Idempotent/resumable. Pass an open -Connection to share one across a batch; otherwise a
        connection is opened per call and disposed. Requires Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionITGlueOrganization (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to itglue_companies (front-end migration 0036).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionITGlueOrganization | Set-ImperionITGlueOrganizationToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'itglue_companies'
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
            Write-ImperionLog -Source 'itglue' -Message "${Table}: 0 rows to write."
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
            Write-ImperionLog -Level Metric -Source 'itglue' -Message "$Table written." -Data @{
                table = $Table; scanned = $tally.scanned; inserted = $tally.inserted; updated = $tally.updated; unchanged = $tally.unchanged
            }
            return $tally
        }
        finally { if ($ownsConnection) { $conn.Dispose() } }
    }
}
