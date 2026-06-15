function Get-ImperionCustomSecurityAttribute {
    <#
    .SYNOPSIS
        Collect a tenant's custom security attribute DEFINITIONS and flatten them to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for the custom-security-attribute taxonomy (issue
        #141; front-end schema issue ImperionCRM#259, table custom_security_attribute_definitions).
        Mints a Graph token for the tenant (GDAP for customer tenants), pages
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
        bronze just lands the taxonomy flat so that merge can read it without parsing
        raw_payload: attribute set, name, type, active state, predefined-only / collection
        flags, and the allowed-value list (joined). Booleans land as 'true'/'false' and the
        allowed-values collection joins to delimited text via the standard scalar coercion
        (bronze flat columns are all-text; the lossless object lives in raw_payload).

        Returns rows; does not write. Requires Initialize-ImperionContext.
    .PARAMETER TenantId
        Tenant to collect from; defaults to the partner tenant. Customer tenants use GDAP.
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
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }

    $token = Get-ImperionGraphToken -TenantId $TenantId
    # $expand=allowedValues carries the predefined value list in one page; the collector joins
    # the active allowed values to a delimited string for the flat hygiene column.
    $definitions = Invoke-ImperionGraphRequest `
        -Uri 'https://graph.microsoft.com/v1.0/directory/customSecurityAttributeDefinitions?$expand=allowedValues' `
        -AccessToken $token

    # Schema issue #259 flat columns (custom_security_attribute_definitions). external_id = id
    # (Graph keys these on `{attributeSet}_{name}`). allowedValues is an array of {id,isActive};
    # join the active ids to a delimited string for the flat column.
    $allowedValueList = {
        param($definition)
        $values = Get-ImperionMember $definition 'allowedValues'
        if (-not $values) { return $null }
        ($values | Where-Object { $_.id } | ForEach-Object { $_.id }) | Join-ImperionValues
    }
    $map = [ordered]@{
        attribute_set       = 'attributeSet'
        attribute_name      = 'name'
        description         = 'description'
        type                = 'type'
        status              = 'status'
        is_collection       = 'isCollection'
        is_searchable       = 'isSearchable'
        use_predefined_values_only = 'usePreDefinedValuesOnly'
        allowed_values      = { param($d) & $allowedValueList $d }
    }

    $rows = @($definitions | ConvertTo-ImperionFlatObject -PropertyMap $map `
            -Source 'm365' -TenantId $TenantId -ExternalIdProperty 'id')

    Write-ImperionLog -Source 'm365' -Message 'Custom security attribute definitions collected.' -Data @{
        tenant = $TenantId; definitions = @($definitions).Count; rows = $rows.Count
    }
    return $rows
}
