function Set-ImperionIntuneManagedAppToBronze {
    <#
    .SYNOPSIS
        Write flattened Intune managed-app rows into the intune_managed_apps bronze table (PENDING front-end migration).
    .DESCRIPTION
        Post-layer writer (CLAUDE.md §6) for the Intune managed-app feed (issue #143 /
        front-end ImperionCRM #261): Intune `mobileApps` land **per app, unreduced** — flat
        publishing/assignment columns (publishing state, featured/assigned flags, publisher,
        version, app archetype) queryable for the device/asset drill-in, full payload
        lossless in raw_payload. This completes the drillable Intune asset detail alongside
        the existing devices / compliance / configuration collectors.

        SCHEMA GATE (front-end ImperionCRM #261): the `intune_managed_apps` table does NOT
        exist yet — it is created by a front-end migration via the schema-handoff process
        (proposed column set below; this repo NEVER creates tables, CLAUDE.md §6). Until it
        lands and the SP is granted write, this writer fails loudly at the upsert — by design
        (deploy-ahead safe; LIVE gated on the on-prem host, issue #102).

        Thin adapter over Invoke-ImperionBronzePost (issue #105 scaffold) using -ColumnSet,
        so a future collector field can never break the insert (extra props survive in
        raw_payload; missing ones land NULL). Idempotent/resumable, change-detected. Pass an
        open -Connection to share one across a batch. Requires Initialize-ImperionContext.
    .PARAMETER Row
        Flat bronze rows from Get-ImperionIntuneManagedApp (accepted from the pipeline).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse. Opened from config + disposed when omitted.
    .PARAMETER Table
        Target bronze table. Defaults to intune_managed_apps (front-end migration pending).
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Get-ImperionIntuneManagedApp | Set-ImperionIntuneManagedAppToBronze
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to the shared scaffold Invoke-ImperionBronzePost via -CallerCmdlet $PSCmdlet (issue #105).')]
    param(
        [Parameter(ValueFromPipeline)][AllowNull()] $Row,
        $Connection,
        [string] $Table = 'intune_managed_apps'
    )

    begin {
        # PROPOSED intune_managed_apps column set (front-end migration pending — ImperionCRM
        # #261 schema handoff): the collector's full flat map (publishing + assignment +
        # archetype + join keys), then the standard envelope.
        $tableColumns = @(
            'app_type', 'display_name', 'description', 'publisher', 'publishing_state',
            'is_featured', 'is_assigned', 'version', 'owner', 'developer', 'notes',
            'information_url', 'privacy_information_url', 'dependent_app_count',
            'superseding_app_count', 'superseded_app_count', 'created_date_time',
            'last_modified_date_time',
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
