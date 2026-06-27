function Get-ImperionAutotaskOpportunityField {
    <#
    .SYNOPSIS
        Probe the Autotask Opportunities entity field metadata (names/types/picklists only — NEVER row data). #1325.
    .DESCRIPTION
        A one-off field-shape probe (the KQM `Get-ImperionKqmFieldName` precedent) that confirms
        the live Autotask **Opportunities** entity shape against the planned `autotask_opportunities`
        bronze (front-end migration 0083) + the renewals epic (ImperionCRM#1304) — the #1325 /
        #430 follow-up. It calls the Autotask REST **entityInformation/fields** endpoint and emits
        a flat table of field metadata ONLY: name, dataType, isRequired, isQueryable, isReadOnly,
        whether it is a picklist + the picklist's active label set.

        **It deliberately does NOT query any Opportunity records.** Field metadata is safe to paste
        into a GitHub issue; row-level Opportunity data is client PII and must never land in an
        issue/PR/commit (system CLAUDE.md §8). To confirm a field's live VALUES, query the live
        read-only DB once the collector has ingested bronze — not from this probe.

        Read-only. Auth = the shared Autotask 3-part header via Get-ImperionAutotaskContext (zone
        discovery + ApiIntegrationCode/UserName/Secret from the SecretStore). Requires
        Initialize-ImperionContext.
    .PARAMETER Entity
        The Autotask entity to probe. Default 'Opportunities'. Exposed so the same probe can
        confirm a related entity's shape (e.g. 'OpportunityCategories') without a new cmdlet.
    .EXAMPLE
        Get-ImperionAutotaskOpportunityField | Format-Table -Auto
    .EXAMPLE
        Get-ImperionAutotaskOpportunityField | Where-Object isPickList | Select-Object name, picklist
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $Entity = 'Opportunities'
    )

    $ctx = Get-ImperionAutotaskContext
    $uri = '{0}/{1}/entityInformation/fields' -f $ctx.ApiBase.TrimEnd('/'), $Entity
    $resp = Invoke-ImperionRestWithRetry -Uri $uri -Headers $ctx.Headers -Method GET

    $fields = @(Get-ImperionMember $resp.Body 'fields')
    if (-not $fields) {
        Write-ImperionLog -Level Warn -Source 'autotask' -Message "No field metadata returned for entity '$Entity'."
        return
    }

    Write-ImperionLog -Level Info -Source 'autotask' -Message "Autotask field probe: $Entity" -Data @{ entity = $Entity; field_count = $fields.Count }

    $fields | ForEach-Object {
        # Active picklist labels only, as value=label pairs — names/labels are schema metadata,
        # not client data. Inactive entries are dropped (they don't constrain new bronze).
        $picks = @(Get-ImperionMember $_ 'picklistValues') | Where-Object { $_ -and $_.isActive -ne $false }
        [pscustomobject][ordered]@{
            name        = $_.name
            dataType    = $_.dataType
            isRequired  = $_.isRequired
            isQueryable = $_.isQueryable
            isReadOnly  = $_.isReadOnly
            isPickList  = $_.isPickList
            length      = $_.length
            picklist    = if ($picks) { ($picks | ForEach-Object { '{0}={1}' -f $_.value, $_.label }) -join '; ' } else { '' }
        }
    }
}
