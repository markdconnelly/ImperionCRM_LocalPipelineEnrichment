function Get-ImperionSensitivityLabel {
    <#
    .SYNOPSIS
        Collect a tenant's Microsoft Purview sensitivity labels and flatten them to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for information-protection posture (issue #141/#375;
        front-end schema issue ImperionCRM#575, table m365_sensitivity_labels). Mints a Graph
        token for the tenant (per-client onboarding app for customer tenants) and flattens each
        label to the standard flat-table envelope, source 'm365', external_id = the label id (a GUID).

        ENDPOINT (app-only, #375): sensitivity labels are exposed app-only ONLY under a per-user
        path — `GET /beta/users/{userId}/security/informationProtection/sensitivityLabels`
        (permission InformationProtectionPolicy.Read.All, read-only). There is NO tenant-root
        list: calling /beta/security/informationProtection/sensitivityLabels with no user resolves
        as user-context with no user → 403 / 404 'policy is empty' / null-id rows (the 2026-06-26
        live failure). So this resolves representative member users and evaluates the published
        labels for the first that returns any — the set is label-policy-scoped, but the default
        policy covers most users, so the first in-scope member is representative for bronze.

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

    # Resolve representative member users (guests can't carry a label policy), then evaluate the
    # published labels for the first that returns any. Cap the probe so a labels-less tenant never
    # walks the whole directory.
    $candidateUsers = @(Invoke-ImperionGraphRequest `
            -Uri 'https://graph.microsoft.com/v1.0/users?$top=25' `
            -AccessToken $token -Select 'id,userType')

    $labels = @()
    $usersProbed = 0
    foreach ($user in $candidateUsers) {
        if ($usersProbed -ge 10) { break }
        $userId = [string](Get-ImperionMember $user 'id')
        if (-not $userId) { continue }
        if ((Get-ImperionMember $user 'userType') -eq 'Guest') { continue }
        $usersProbed++
        $found = @(Invoke-ImperionGraphRequest `
                -Uri "https://graph.microsoft.com/beta/users/$userId/security/informationProtection/sensitivityLabels" `
                -AccessToken $token)
        if ($found.Count -gt 0) { $labels = $found; break }
    }

    # Drop any label without an id — label_id is NOT NULL (a null-id row 23502'd IPG's whole batch,
    # #375); the bad row is skipped, the rest still land. Same defensive class as the #366 skip.
    $labels = @($labels | Where-Object { Get-ImperionMember $_ 'id' })

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
        tenant = $TenantId; usersProbed = $usersProbed; labels = @($labels).Count; rows = $rows.Count
    }
    return $rows
}
