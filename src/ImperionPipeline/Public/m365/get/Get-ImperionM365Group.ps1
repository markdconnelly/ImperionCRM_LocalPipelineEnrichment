function Get-ImperionM365Group {
    <#
    .SYNOPSIS
        Collect the Entra/M365 group inventory (Graph /groups) and flatten it to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for the directory group inventory (issue #150,
        split from #139; front-end migration 0079 / issue #257). Pages Graph /groups —
        every group in the tenant (Microsoft 365, security, mail-enabled security, and
        dynamic) — and flattens each to the standard flat-table envelope, source 'm365'
        (the entra_auth_methods convention), external_id = the Entra group object id.

        A $select is sent because several migration-0079 columns are NOT default-returned
        by /groups (membershipRule, membershipRuleProcessingState, isAssignableToRole) —
        without it those land NULL even when set. The directory-membership EDGES are a
        separate collector (Get-ImperionM365GroupMember, issue #139) — this getter is the
        group objects only.

        Collections (groupTypes) join to delimited text via the standard scalar coercion;
        booleans land 'true'/'false' (bronze flat columns are all-text; lossless types
        live in raw_payload).

        Returns rows; does not write. Requires Initialize-ImperionContext.
    .PARAMETER TenantId
        Tenant to authenticate against; defaults to the partner tenant.
    .OUTPUTS
        Flat bronze rows (source 'm365') ready for Set-ImperionM365GroupToBronze.
    .EXAMPLE
        Get-ImperionM365Group | Set-ImperionM365GroupToBronze
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.LocalTenantId }

    # $select the exact migration-0079 source properties — the advanced ones
    # (membershipRule*, isAssignableToRole) are omitted from the default projection.
    $select = @(
        'id', 'displayName', 'mailNickname', 'mail', 'description', 'groupTypes',
        'securityEnabled', 'mailEnabled', 'visibility', 'classification',
        'isAssignableToRole', 'membershipRule', 'membershipRuleProcessingState',
        'onPremisesSyncEnabled', 'createdDateTime', 'renewedDateTime', 'expirationDateTime'
    ) -join ','

    $token = Get-ImperionGraphToken -TenantId $TenantId
    $groups = Invoke-ImperionGraphRequest `
        -Uri "https://graph.microsoft.com/v1.0/groups?`$select=$select" `
        -AccessToken $token

    # Migration-0079 flat columns; arrays/booleans/dates coerced by ConvertTo-ImperionFlatObject.
    $map = [ordered]@{
        display_name                     = 'displayName'
        mail_nickname                    = 'mailNickname'
        mail                             = 'mail'
        description                      = 'description'
        group_types                      = 'groupTypes'
        security_enabled                 = 'securityEnabled'
        mail_enabled                     = 'mailEnabled'
        visibility                       = 'visibility'
        classification                   = 'classification'
        is_assignable_to_role            = 'isAssignableToRole'
        membership_rule                  = 'membershipRule'
        membership_rule_processing_state = 'membershipRuleProcessingState'
        on_premises_sync_enabled         = 'onPremisesSyncEnabled'
        created_date_time                = 'createdDateTime'
        renewed_date_time                = 'renewedDateTime'
        expiration_date_time             = 'expirationDateTime'
    }

    $rows = @($groups | ConvertTo-ImperionFlatObject -PropertyMap $map `
            -Source 'm365' -TenantId $TenantId -ExternalIdProperty 'id')

    Write-ImperionLog -Source 'm365' -Message 'Entra/M365 group inventory collected.' -Data @{
        groups = @($groups).Count; rows = $rows.Count
    }
    return $rows
}
