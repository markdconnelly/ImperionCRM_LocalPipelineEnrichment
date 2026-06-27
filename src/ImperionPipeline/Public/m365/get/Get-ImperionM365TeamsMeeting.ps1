function Get-ImperionM365TeamsMeeting {
    <#
    .SYNOPSIS
        Collect online (Teams) meetings for one or more users and flatten them to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6, the verbose m365 communication path). For each user it
        pages calendar /events that are online meetings in the window and flattens EVERY survivor to
        the standard flat-table envelope (target: silver meeting, platform teams; source m365_teams).
        Returns rows; does not write. Requires Initialize-ImperionContext.

        CAPTURE MODEL (ADR-0126 / FE #1366, this repo's #380): meetings are pulled from Imperion's
        OWN tenant and the client-scoping filter is applied LATER, at the silver layer, against
        `account_domain` + onboarded contacts — front-end #1369. This collector therefore does NOT
        filter at collection: the old collection-time `Test-ImperionCrossOrgComm` client-domain gate
        was the bug behind the 0-row prod state (#380) — with no client domains configured it
        dropped every meeting. Over-collect at bronze; narrow at silver (CLAUDE.md §5 bronze rule).
    .PARAMETER User
        User UPNs/ids whose meetings to collect.
    .PARAMETER TenantId
        Tenant to authenticate against; defaults to the partner tenant.
    .PARAMETER SinceDays
        Look-back window on the meeting start. Default 30.
    .EXAMPLE
        Get-ImperionM365TeamsMeeting -User 'ada@imperionllc.com'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string[]] $User,
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
            # ADR-0126: keep every home-tenant online meeting; the client filter is a silver concern (FE #1369).
            $ev | Add-Member -NotePropertyName '_imperionUser' -NotePropertyValue $u -Force
            $kept.Add($ev)
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
