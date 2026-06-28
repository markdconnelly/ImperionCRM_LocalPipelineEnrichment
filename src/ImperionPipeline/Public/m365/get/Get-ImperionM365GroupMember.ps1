function Get-ImperionM365GroupMember {
    <#
    .SYNOPSIS
        Expand Entra/M365 group membership (Graph /groups/{id}/members) into bronze edge rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for directory group MEMBERSHIP (issue #139;
        front-end migration 0079 / issue #257). Enumerates the tenant's groups (ids only),
        then expands each group's direct members and flattens every membership to one
        bronze EDGE row, source 'm365'.

        A membership has no single natural id, so external_id is the collector-built
        '<group id>/<member id>' composite (the 0079 contract; matches the 0078
        composite-site-id precedent). The flat parts carry the join keys:
        group_external_id = the parent Entra group object id; member_external_id = the
        member directory object id, which equals m365_contacts.external_ref = the Entra
        user object id — how a membership reaches the silver contact (the front-end
        Directory-groups surface, #257). member_type is the Graph @odata.type, so non-user
        members (nested groups, devices, service principals) are retained and
        distinguishable; only user members resolve to a contact.

        Returns rows; does not write. Requires Initialize-ImperionContext.
    .PARAMETER TenantId
        Tenant to authenticate against; defaults to the partner tenant.
    .OUTPUTS
        Flat bronze edge rows (source 'm365') ready for Set-ImperionM365GroupMemberToBronze.
    .EXAMPLE
        Get-ImperionM365GroupMember | Set-ImperionM365GroupMemberToBronze
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.LocalTenantId }

    $token = Get-ImperionGraphToken -TenantId $TenantId

    # Group ids only — the group objects themselves are a separate collector (#150).
    $groups = Invoke-ImperionGraphRequest `
        -Uri 'https://graph.microsoft.com/v1.0/groups?$select=id' `
        -AccessToken $token

    # Migration-0079 m365_group_members flat columns (all paths on the synthetic edge object).
    $map = [ordered]@{
        group_external_id          = 'group_external_id'
        member_external_id         = 'member_external_id'
        member_type                = 'member_type'
        member_display_name        = 'member_display_name'
        member_user_principal_name = 'member_user_principal_name'
        member_mail                = 'member_mail'
    }

    $skippedMembers = 0
    $edges = foreach ($group in $groups) {
        $groupId = $group.id
        $members = Invoke-ImperionGraphRequest `
            -Uri "https://graph.microsoft.com/v1.0/groups/$groupId/members?`$select=id,displayName,userPrincipalName,mail" `
            -AccessToken $token
        foreach ($member in $members) {
            # Synthetic edge: renamed scalars (avoids the '@odata.type' dotted-path split)
            # plus the composite id used as external_id. raw_payload keeps the full member.
            # Members are heterogeneous directory objects — a non-user member (nested group,
            # device, servicePrincipal) has no userPrincipalName/mail, so read every field
            # through the safe accessor (direct $member.prop throws under StrictMode). #337
            $memberId = Get-ImperionMember $member 'id'
            # A membership with no member directory id can't form a valid edge: member_external_id
            # is NOT NULL in m365_group_members (migration 0079) and the composite external_id would
            # collapse to '<group>/'. Graph occasionally returns an id-less member (an inaccessible /
            # partially-readable directory object); skip it so one such member never 23502s the whole
            # tenant's membership upsert (#366). An id-less member carries no usable join key, so it
            # is dropped entirely; skips are counted into the run log.
            if ([string]::IsNullOrEmpty([string]$memberId)) {
                $skippedMembers++
                continue
            }
            [pscustomobject]@{
                group_external_id          = $groupId
                member_external_id         = $memberId
                member_type                = Get-ImperionMember $member '@odata.type'
                member_display_name        = Get-ImperionMember $member 'displayName'
                member_user_principal_name = Get-ImperionMember $member 'userPrincipalName'
                member_mail                = Get-ImperionMember $member 'mail'
                edge_external_id           = "$groupId/$memberId"
                member                     = $member
            }
        }
    }

    $rows = @($edges | ConvertTo-ImperionFlatObject -PropertyMap $map `
            -Source 'm365' -TenantId $TenantId -ExternalIdProperty 'edge_external_id')

    Write-ImperionLog -Source 'm365' -Message 'Entra/M365 group membership expanded.' -Data @{
        groups = @($groups).Count; edges = $rows.Count; skipped_members = $skippedMembers
    }
    return $rows
}
