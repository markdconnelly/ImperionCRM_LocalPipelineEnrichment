function Get-ImperionMetaLead {
    <#
    .SYNOPSIS
        Collect submitted Meta Lead Ads (instant-form leads) per form and flatten them to meta_lead_ads bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for the Meta Lead Ads source (LP #362,
        transferred from backend #424; permission leads_retrieval). Takes leadgen form ids
        from the pipeline (the rows Get-ImperionMetaLeadForm emits bind by their external_id
        property) or an explicit -FormId array, pages /{form-id}/leads per form, and
        flattens to the meta_lead_ads column set (front-end migration 0207). Each lead =
        field_data answers + ad/campaign/form ids + created_time. The form submitter IS the
        lead (the DM-sender precedent, 0075). Target: bronze `meta_lead_ads` → silver
        lead_hook / lead_capture_event via Invoke-ImperionMetaLeadAdsMerge (local merge
        ownership, ADR-0026; idempotent on the Meta leadgen id). Returns rows; does not
        write. Requires Initialize-ImperionContext.

        PII: field_data carries the submitter's name/email/phone/free-text. These rows are
        PII-adjacent — never log their contents (ADR-0086); only counts/ids are logged.

        ASSUMED-FIELD-NAMES caveat: fields follow Meta's published leads reference; anything
        the token cannot read lands NULL in the flat column and survives in raw_payload.
        Verify against a live first run.
    .PARAMETER FormId
        Leadgen form ids to collect leads for. Accepts pipeline input — including the
        flattened form rows themselves (binds external_id by property name). Also stamped
        onto each lead row as form_id.
    .PARAMETER PageId
        Optional Page id stamped onto each row as page_id (for the merge's hook config).
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant.
    .PARAMETER Token
        Meta page token override. Defaults to the SecretStore resolution (ADR-0013).
    .PARAMETER MaxPages
        Paging cap per form forwarded to the connect layer. Default 100.
    .EXAMPLE
        Get-ImperionMetaLeadForm -PageId $pageId -Token $t | Get-ImperionMetaLead -PageId $pageId -Token $t
    .EXAMPLE
        Get-ImperionMetaLead -FormId '123456' -Token $pageToken
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('external_id')][string[]] $FormId,
        [string] $PageId,
        [string] $TenantId,
        [string] $Token,
        [int] $MaxPages = 100
    )

    begin {
        $cfg = Get-ImperionConfig
        if (-not $TenantId) { $TenantId = $cfg.LocalTenantId }
        $Token = Resolve-ImperionMetaToken -Token $Token

        # Pull a named answer out of Meta's field_data array: [{ name, values: [..] }, ...].
        # Tolerant of absent/empty values; returns the first value or $null.
        $fieldValue = {
            param($lead, [string[]] $names)
            $fieldData = @(Get-ImperionMember $lead 'field_data')
            foreach ($name in $names) {
                foreach ($field in $fieldData) {
                    if ([string](Get-ImperionMember $field 'name') -eq $name) {
                        $values = @(Get-ImperionMember $field 'values')
                        if ($values.Count -gt 0) { return [string]$values[0] }
                    }
                }
            }
            return $null
        }

        $jsonScalar = {
            param($value)
            if ($null -eq $value) { return $null }
            if ($value -is [string]) { return $value }
            $value | ConvertTo-Json -Compress -Depth 20
        }

        $map = [ordered]@{
            form_id       = '_imperionFormId'
            page_id       = '_imperionPageId'
            ad_id         = 'ad_id'
            ad_name       = 'ad_name'
            adset_id      = 'adset_id'
            campaign_id   = 'campaign_id'
            campaign_name = 'campaign_name'
            platform      = 'platform'
            is_organic    = 'is_organic'
            field_data    = { & $jsonScalar (Get-ImperionMember $_ 'field_data') }
            full_name     = { & $fieldValue $_ @('full_name', 'name') }
            email         = { & $fieldValue $_ @('email') }
            phone_number  = { & $fieldValue $_ @('phone_number', 'phone') }
            created_time  = 'created_time'
        }
        # Bracketed field selector — Meta returns the answers under `field_data`.
        $fields = 'id,created_time,ad_id,ad_name,adset_id,campaign_id,campaign_name,platform,is_organic,field_data'
    }
    process {
        foreach ($id in $FormId) {
            if (-not $id) { continue }
            $uri = '{0}/leads?fields={1}&limit=100' -f [uri]::EscapeDataString($id), $fields
            $leads = @(Invoke-ImperionMetaRequest -Token $Token -Uri $uri -MaxPages $MaxPages)
            foreach ($lead in $leads) {
                $lead | Add-Member -NotePropertyName '_imperionFormId' -NotePropertyValue $id -Force
                $lead | Add-Member -NotePropertyName '_imperionPageId' -NotePropertyValue $PageId -Force
            }
            $leads | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'meta_lead_ad' -TenantId $TenantId -ExternalIdProperty 'id'
        }
    }
}
