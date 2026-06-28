function Get-ImperionM365TeamsChat {
    <#
    .SYNOPSIS
        Collect Imperion<->client Teams chats for one or more users and flatten them to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6, the verbose m365 communication path). For each user it
        lists /chats (with members expanded), applies the cross-org noise filter
        (Test-ImperionCrossOrgComm over the chat members' addresses) so ONLY Imperion<->client
        chats are kept, and flattens survivors to the standard flat-table envelope (target: silver
        interaction, source m365_teams). Returns rows; does not write. Requires
        Initialize-ImperionContext.
    .PARAMETER User
        User UPNs/ids whose chats to collect.
    .PARAMETER Mode
        ImperionTenant (default, keep chats with a known client domain) or ClientTenant (GDAP,
        keep chats with @imperionllc.com).
    .PARAMETER ClientDomain
        Known client domains (ImperionTenant mode), from the silver account/tenant map.
    .PARAMETER ImperionDomain
        The Imperion domain. Default 'imperionllc.com'.
    .PARAMETER TenantId
        Tenant to authenticate against; defaults to the partner tenant. Customer tenants use GDAP.
    .EXAMPLE
        Get-ImperionM365TeamsChat -User 'ada@imperionllc.com' -Mode ImperionTenant -ClientDomain 'acme.com'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string[]] $User,
        [ValidateSet('ImperionTenant', 'ClientTenant')][string] $Mode = 'ImperionTenant',
        [string[]] $ClientDomain = @(),
        [string] $ImperionDomain = 'imperionllc.com',
        [string] $TenantId
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.LocalTenantId }
    $token = Get-ImperionGraphToken -TenantId $TenantId

    $kept = [System.Collections.Generic.List[object]]::new()
    foreach ($u in $User) {
        $uri = 'https://graph.microsoft.com/v1.0/users/{0}/chats?$expand=members' -f [uri]::EscapeDataString($u)
        $chats = Invoke-ImperionGraphRequest -Uri $uri -AccessToken $token

        foreach ($chat in $chats) {
            $memberEmails = @(Get-ImperionMember $chat 'members') | Where-Object { $_ } |
                ForEach-Object { Get-ImperionPropertyPath -InputObject $_ -Path 'email' } | Where-Object { $_ }

            if (Test-ImperionCrossOrgComm -Participant @($memberEmails) -Mode $Mode -ClientDomain $ClientDomain -ImperionDomain $ImperionDomain) {
                $chat | Add-Member -NotePropertyName '_imperionUser' -NotePropertyValue $u -Force
                $kept.Add($chat)
            }
        }
    }

    $map = [ordered]@{
        user                   = { param($c) Get-ImperionMember $c '_imperionUser' }
        topic                  = 'topic'
        chat_type              = 'chatType'
        member_emails          = { param($c) (@(Get-ImperionMember $c 'members') | Where-Object { $_ } | ForEach-Object { Get-ImperionPropertyPath -InputObject $_ -Path 'email' }) | Join-ImperionValues }
        member_names           = { param($c) (@(Get-ImperionMember $c 'members') | Where-Object { $_ } | ForEach-Object { Get-ImperionPropertyPath -InputObject $_ -Path 'displayName' }) | Join-ImperionValues }
        created_date_time      = 'createdDateTime'
        last_updated_date_time = 'lastUpdatedDateTime'
        web_url                = 'webUrl'
    }

    $kept | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'm365_teams' -TenantId $TenantId -ExternalIdProperty 'id'
}
