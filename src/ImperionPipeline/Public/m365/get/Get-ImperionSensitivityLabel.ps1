function Get-ImperionSensitivityLabel {
    <#
    .SYNOPSIS
        Collect a tenant's Microsoft Purview sensitivity labels and flatten them to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for information-protection posture (issue #141;
        front-end schema issue ImperionCRM#259, table sensitivity_labels). Mints a Graph token
        for the tenant (GDAP for customer tenants), pages
        /security/informationProtection/sensitivityLabels — application permission
        SensitivityLabels.Read.All, read-only — and flattens each label to the standard
        flat-table envelope, source 'm365', external_id = the label id (a GUID).

        Sensitivity labels are the data-classification taxonomy a tenant publishes (Public /
        Confidential / Highly Confidential and the like). The benchmark-vs-golden classification
        runs in the front-end posture merge per the golden-baseline pattern (issue #259); bronze
        just lands the taxonomy flat so that merge can read it without parsing raw_payload:
        name, priority/sensitivity ordering, active/applies-to state, and the parent-label id
        (labels nest), surface as flat text. Booleans land as 'true'/'false' and collections
        join to delimited text via the standard scalar coercion (bronze flat columns are
        all-text; the lossless object — rights, auto-labelling, the full sublabel tree — lives
        in raw_payload).

        Returns rows; does not write. Requires Initialize-ImperionContext.
    .PARAMETER TenantId
        Tenant to collect from; defaults to the partner tenant. Customer tenants use GDAP.
    .OUTPUTS
        Flat bronze rows (source 'm365') ready for Set-ImperionSensitivityLabelToBronze.
    .EXAMPLE
        Get-ImperionSensitivityLabel | Set-ImperionSensitivityLabelToBronze
    .EXAMPLE
        Get-ImperionSensitivityLabel -TenantId $customerTenantId
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }

    $token = Get-ImperionGraphToken -TenantId $TenantId
    $labels = Invoke-ImperionGraphRequest `
        -Uri 'https://graph.microsoft.com/v1.0/security/informationProtection/sensitivityLabels' `
        -AccessToken $token

    # Schema issue #259 flat columns (sensitivity_labels); collections/booleans coerced by
    # ConvertTo-ImperionFlatObject. external_id = id (the label GUID). parent.id surfaces the
    # label nesting (sublabels) without walking the tree; the full tree lives in raw_payload.
    $map = [ordered]@{
        label_name        = 'name'
        display_name      = 'displayName'
        description        = 'description'
        is_active         = 'isActive'
        is_appendable     = 'isAppendable'
        sensitivity       = 'sensitivity'
        tooltip           = 'tooltip'
        applies_to        = 'appliesTo'
        parent_label_id   = 'parent.id'
        parent_label_name = 'parent.name'
    }

    $rows = @($labels | ConvertTo-ImperionFlatObject -PropertyMap $map `
            -Source 'm365' -TenantId $TenantId -ExternalIdProperty 'id')

    Write-ImperionLog -Source 'm365' -Message 'Sensitivity labels collected.' -Data @{
        tenant = $TenantId; labels = @($labels).Count; rows = $rows.Count
    }
    return $rows
}
