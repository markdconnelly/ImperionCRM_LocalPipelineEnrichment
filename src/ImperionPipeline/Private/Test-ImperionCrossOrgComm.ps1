function Test-ImperionCrossOrgComm {
    <#
    .SYNOPSIS
        Decide whether a communication is a relevant Imperion<->client cross-org exchange (private).
    .DESCRIPTION
        The noise-control predicate for the m365 communication collectors (mail / Teams chats /
        Teams meetings). The goal is to keep ONLY communication that crosses the Imperion/client
        boundary and drop internal-only chatter:
          * ImperionTenant mode (collecting from @imperionllc.com): relevant when any participant
            is on a KNOWN CLIENT domain.
          * ClientTenant mode (collecting from a customer tenant via GDAP): relevant when any
            participant is on the Imperion domain (@imperionllc.com).
        Pure function over the participant address list — fully unit-testable. Domain comparison
        is case-insensitive; blank/invalid addresses are ignored.
    .PARAMETER Participant
        All participant email addresses on the communication (sender + recipients for mail;
        members for chats; organizer + attendees for meetings).
    .PARAMETER Mode
        'ImperionTenant' when the mailbox/tenant being collected is @imperionllc.com;
        'ClientTenant' when collecting a customer tenant via GDAP.
    .PARAMETER ImperionDomain
        The Imperion domain. Default 'imperionllc.com'.
    .PARAMETER ClientDomain
        The set of known client domains (used in ImperionTenant mode; derived from silver account/tenant map).
    .EXAMPLE
        Test-ImperionCrossOrgComm -Participant @('ada@imperionllc.com','sam@acme.com') -Mode ImperionTenant -ClientDomain 'acme.com'
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [string[]] $Participant,
        [Parameter(Mandatory)][ValidateSet('ImperionTenant', 'ClientTenant')][string] $Mode,
        [string] $ImperionDomain = 'imperionllc.com',
        [string[]] $ClientDomain = @()
    )

    $domains = @($Participant) |
        Where-Object { $_ -and ($_ -like '*@*') } |
        ForEach-Object { (($_ -split '@')[-1]).Trim().ToLowerInvariant() } |
        Where-Object { $_ }

    if ($Mode -eq 'ImperionTenant') {
        $clientSet = @($ClientDomain) | Where-Object { $_ } | ForEach-Object { $_.Trim().ToLowerInvariant() }
        return [bool](@($domains | Where-Object { $_ -in $clientSet }).Count)
    }

    $imperion = $ImperionDomain.Trim().ToLowerInvariant()
    return [bool](@($domains | Where-Object { $_ -eq $imperion }).Count)
}
