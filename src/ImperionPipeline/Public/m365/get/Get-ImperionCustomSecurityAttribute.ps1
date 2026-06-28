function Get-ImperionCustomSecurityAttribute {
    <#
    .SYNOPSIS
        Collect a tenant's custom security attribute DEFINITIONS and flatten them to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for the custom-security-attribute taxonomy (issue
        #141; front-end schema issue ImperionCRM#575, table entra_custom_security_attributes).
        Mints a Graph token for the tenant (per-client onboarding app for customer tenants), pages
        /directory/customSecurityAttributeDefinitions with $expand=allowedValues — application
        permission CustomSecAttributeDefinition.Read.All, read-only — and flattens each
        definition to the standard flat-table envelope, source 'm365', external_id = the
        definition id (`{attributeSet}_{attributeName}`).

        DEFINITIONS, not assignments. A custom security attribute *definition* is the tenant's
        attribute taxonomy (which sets exist, each attribute's type/status/whether it is a
        free-form value or a predefined list). Per-principal *assignments* (the key=value tags
        on individual users/SPs) are a heavier, principal-joined, PII-bearing surface deferred
        to a follow-up (CustomSecAttributeAssignment.Read.All) — see the integration doc. The
        benchmark-vs-golden classification runs in the front-end posture merge (issue #259);
        bronze just lands the applied #575 columns flat — attribute_set, name, data_type,
        status — so that merge can read them without parsing raw_payload. The rest (description,
        collection / searchable / predefined-only flags, the allowed-value list) stays lossless
        in raw_payload (bronze flat columns are all-text).

        Returns rows; does not write. Requires Initialize-ImperionContext.
    .PARAMETER TenantId
        Tenant to collect from; defaults to the partner tenant. Customer tenants use the
        per-client onboarding app.
    .OUTPUTS
        Flat bronze rows (source 'm365') ready for Set-ImperionCustomSecurityAttributeToBronze.
    .EXAMPLE
        Get-ImperionCustomSecurityAttribute | Set-ImperionCustomSecurityAttributeToBronze
    .EXAMPLE
        Get-ImperionCustomSecurityAttribute -TenantId $customerTenantId
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.LocalTenantId }

    $token = Get-ImperionGraphToken -TenantId $TenantId
    # $expand=allowedValues carries the predefined value list in one page; it survives lossless
    # in raw_payload (the applied #575 flat columns do not include it).
    $definitions = Invoke-ImperionGraphRequest `
        -Uri 'https://graph.microsoft.com/v1.0/directory/customSecurityAttributeDefinitions?$expand=allowedValues' `
        -AccessToken $token

    # Drop any definition missing attributeSet/name — both are NOT NULL (a null attribute_set
    # 23502'd IPG's whole batch, #375). Skip the bad row, keep the rest. Same class as #366.
    $definitions = @($definitions | Where-Object {
            (Get-ImperionMember $_ 'attributeSet') -and (Get-ImperionMember $_ 'name')
        })

    # Applied #575 flat columns (entra_custom_security_attributes): attribute_set, name,
    # data_type, status. external_id = id (Graph keys these on `{attributeSet}_{name}`).
    # data_type maps from the Graph `type` property. The rest stays lossless in raw_payload.
    $map = [ordered]@{
        attribute_set = 'attributeSet'
        name          = 'name'
        data_type     = 'type'
        status        = 'status'
    }

    $rows = @($definitions | ConvertTo-ImperionFlatObject -PropertyMap $map `
            -Source 'm365' -TenantId $TenantId -ExternalIdProperty 'id')

    Write-ImperionLog -Source 'm365' -Message 'Custom security attribute definitions collected.' -Data @{
        tenant = $TenantId; definitions = @($definitions).Count; rows = $rows.Count
    }
    return $rows
}
