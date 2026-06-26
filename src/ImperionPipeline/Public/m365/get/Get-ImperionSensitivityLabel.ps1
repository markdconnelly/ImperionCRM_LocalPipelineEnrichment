function Get-ImperionSensitivityLabel {
    <#
    .SYNOPSIS
        Collect a tenant's Microsoft Purview sensitivity labels and flatten them to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for information-protection posture (issue #141;
        front-end schema issue ImperionCRM#575, table m365_sensitivity_labels). Mints a Graph
        token for the tenant (per-client onboarding app for customer tenants), pages
        /beta/security/informationProtection/sensitivityLabels — application permission
        SensitivityLabels.Read.All, read-only — and flattens each label to the standard
        flat-table envelope, source 'm365', external_id = the label id (a GUID).

        The endpoint is beta-only: the /v1.0 path 400s 'segment informationProtection not found'
        (same class as the intune detectedApps fix, #369).

        Sensitivity labels are the data-classification taxonomy a tenant publishes (Public /
        Confidential / Highly Confidential and the like). The benchmark-vs-golden classification
        runs in the front-end posture merge per the golden-baseline pattern (issue #575); bronze
        just lands the applied #575 columns flat — label_id, name, priority ordering, active
        state — so that merge can read them without parsing raw_payload. The lossless object
        (description, tooltip, applies-to, rights, auto-labelling, the full sublabel tree) lives
        in raw_payload; booleans land as 'true'/'false' via the standard scalar coercion.

        Returns rows; does not write. Requires Initialize-ImperionContext.
    .PARAMETER TenantId
        Tenant to collect from; defaults to the partner tenant. Customer tenants use the
        per-client onboarding app.
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
        -Uri 'https://graph.microsoft.com/beta/security/informationProtection/sensitivityLabels' `
        -AccessToken $token

    # Applied #575 flat columns (m365_sensitivity_labels): label_id, name, priority, is_active.
    # external_id is also the label GUID (-ExternalIdProperty 'id'); label_id repeats it as a
    # first-class flat column. priority = Graph `sensitivity` (the label ordering). Everything
    # else (display name, description, tooltip, applies-to, the sublabel tree) stays lossless
    # in raw_payload; the boolean coerces to 'true'/'false' via ConvertTo-ImperionFlatObject.
    $map = [ordered]@{
        label_id  = 'id'
        name      = 'name'
        priority  = 'sensitivity'
        is_active = 'isActive'
    }

    $rows = @($labels | ConvertTo-ImperionFlatObject -PropertyMap $map `
            -Source 'm365' -TenantId $TenantId -ExternalIdProperty 'id')

    Write-ImperionLog -Source 'm365' -Message 'Sensitivity labels collected.' -Data @{
        tenant = $TenantId; labels = @($labels).Count; rows = $rows.Count
    }
    return $rows
}
