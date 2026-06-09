function Get-ImperionM365TeamsMeeting {
    <#
    .SYNOPSIS
        Collect Imperion<->client Teams meetings for one or more users and flatten them to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6, the verbose m365 communication path). For each user it
        pages calendar /events that are online meetings in the window, applies the cross-org noise
        filter (Test-ImperionCrossOrgComm over organizer + attendee addresses) so ONLY
        Imperion<->client meetings are kept, and flattens survivors to the standard flat-table
        envelope (target: silver meeting, platform teams; source m365_teams). Returns rows; does
        not write. Requires Initialize-ImperionContext.
    .PARAMETER User
        User UPNs/ids whose meetings to collect.
    .PARAMETER Mode
        ImperionTenant (default) or ClientTenant — selects the filter direction.
    .PARAMETER ClientDomain
        Known client domains (ImperionTenant mode), from the silver account/tenant map.
    .PARAMETER ImperionDomain
        The Imperion domain. Default 'imperionllc.com'.
    .PARAMETER TenantId
        Tenant to authenticate against; defaults to the partner tenant. Customer tenants use GDAP.
    .PARAMETER SinceDays
        Look-back window on the meeting start. Default 30.
    .EXAMPLE
        Get-ImperionM365TeamsMeeting -User 'ada@imperionllc.com' -Mode ImperionTenant -ClientDomain 'acme.com'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string[]] $User,
        [ValidateSet('ImperionTenant', 'ClientTenant')][string] $Mode = 'ImperionTenant',
        [string[]] $ClientDomain = @(),
        [string] $ImperionDomain = 'imperionllc.com',
        [string] $TenantId,
        [int] $SinceDays = 30
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }
    $token = Get-ImperionGraphToken -TenantId $TenantId
    $sinceIso = (Get-Date).AddDays(-$SinceDays).ToString('yyyy-MM-ddTHH:mm:ssZ')
    $select = 'id,subject,organizer,attendees,start,end,isOnlineMeeting,onlineMeetingProvider,onlineMeeting,isCancelled,webLink'

    $kept = [System.Collections.Generic.List[object]]::new()
    foreach ($u in $User) {
        $uri = "https://graph.microsoft.com/v1.0/users/{0}/events?`$filter=isOnlineMeeting eq true and start/dateTime ge '{1}'&`$select={2}&`$top=50" -f [uri]::EscapeDataString($u), $sinceIso, $select
        $events = Invoke-ImperionGraphRequest -Uri $uri -AccessToken $token

        foreach ($ev in $events) {
            $participants = [System.Collections.Generic.List[string]]::new()
            $organizer = Get-ImperionPropertyPath -InputObject $ev -Path 'organizer.emailAddress.address'
            if ($organizer) { $participants.Add($organizer) }
            @(Get-ImperionMember $ev 'attendees') | Where-Object { $_ } |
                ForEach-Object { Get-ImperionPropertyPath -InputObject $_ -Path 'emailAddress.address' } |
                Where-Object { $_ } | ForEach-Object { $participants.Add($_) }

            if (Test-ImperionCrossOrgComm -Participant $participants.ToArray() -Mode $Mode -ClientDomain $ClientDomain -ImperionDomain $ImperionDomain) {
                $ev | Add-Member -NotePropertyName '_imperionUser' -NotePropertyValue $u -Force
                $kept.Add($ev)
            }
        }
    }

    $map = [ordered]@{
        user                    = { param($e) Get-ImperionMember $e '_imperionUser' }
        subject                 = 'subject'
        organizer_address       = { param($e) Get-ImperionPropertyPath -InputObject $e -Path 'organizer.emailAddress.address' }
        attendee_addresses      = { param($e) (@(Get-ImperionMember $e 'attendees') | Where-Object { $_ } | ForEach-Object { Get-ImperionPropertyPath -InputObject $_ -Path 'emailAddress.address' }) | Join-ImperionValues }
        start_date_time         = 'start.dateTime'
        end_date_time           = 'end.dateTime'
        is_online_meeting       = 'isOnlineMeeting'
        online_meeting_provider = 'onlineMeetingProvider'
        join_url                = 'onlineMeeting.joinUrl'
        is_cancelled            = 'isCancelled'
        web_link                = 'webLink'
    }

    $kept | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'm365_teams' -TenantId $TenantId -ExternalIdProperty 'id'
}
