function Get-ImperionM365Mail {
    <#
    .SYNOPSIS
        Collect Imperion<->client emails from one or more mailboxes and flatten them to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6, the verbose m365 communication path). For each mailbox
        it pages recent /messages, applies the cross-org noise filter (Test-ImperionCrossOrgComm)
        so ONLY Imperion<->client mail is kept, and flattens the survivors to the standard
        flat-table envelope (target: silver interaction, source m365_email). Returns rows; does
        not write. Requires Initialize-ImperionContext.

        Two collection shapes:
          * Imperion tenant: -Mode ImperionTenant -ClientDomain <known client domains> over
            @imperionllc.com mailboxes — keeps mail involving a client domain.
          * Client tenant (GDAP): -Mode ClientTenant -TenantId <customer> over that tenant's
            mailboxes — keeps mail involving @imperionllc.com.
    .PARAMETER Mailbox
        Mailbox UPNs/ids to collect (one scheduled task can fan a set of mailboxes).
    .PARAMETER Mode
        ImperionTenant (default) or ClientTenant — selects the filter direction.
    .PARAMETER ClientDomain
        Known client domains (ImperionTenant mode), from the silver account/tenant map.
    .PARAMETER ImperionDomain
        The Imperion domain. Default 'imperionllc.com'.
    .PARAMETER TenantId
        Tenant to authenticate against; defaults to the partner tenant. Customer tenants use GDAP.
    .PARAMETER SinceDays
        Look-back window on receivedDateTime. Default 7.
    .EXAMPLE
        Get-ImperionM365Mail -Mailbox 'ada@imperionllc.com' -Mode ImperionTenant -ClientDomain 'acme.com'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string[]] $Mailbox,
        [ValidateSet('ImperionTenant', 'ClientTenant')][string] $Mode = 'ImperionTenant',
        [string[]] $ClientDomain = @(),
        [string] $ImperionDomain = 'imperionllc.com',
        [string] $TenantId,
        [int] $SinceDays = 7
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }
    $token = Get-ImperionGraphToken -TenantId $TenantId
    $sinceIso = (Get-Date).AddDays(-$SinceDays).ToString('yyyy-MM-ddTHH:mm:ssZ')
    $select = 'id,subject,from,toRecipients,ccRecipients,receivedDateTime,sentDateTime,conversationId,hasAttachments,importance,isRead,webLink'

    $kept = [System.Collections.Generic.List[object]]::new()
    foreach ($mb in $Mailbox) {
        $uri = 'https://graph.microsoft.com/v1.0/users/{0}/messages?$filter=receivedDateTime ge {1}&$select={2}&$top=50' -f [uri]::EscapeDataString($mb), $sinceIso, $select
        $messages = Invoke-ImperionGraphRequest -Uri $uri -AccessToken $token

        foreach ($m in $messages) {
            $participants = [System.Collections.Generic.List[string]]::new()
            $from = Get-ImperionPropertyPath -InputObject $m -Path 'from.emailAddress.address'
            if ($from) { $participants.Add($from) }
            foreach ($prop in 'toRecipients', 'ccRecipients') {
                @(Get-ImperionMember $m $prop) | Where-Object { $_ } |
                    ForEach-Object { Get-ImperionPropertyPath -InputObject $_ -Path 'emailAddress.address' } |
                    Where-Object { $_ } | ForEach-Object { $participants.Add($_) }
            }

            if (Test-ImperionCrossOrgComm -Participant $participants.ToArray() -Mode $Mode -ClientDomain $ClientDomain -ImperionDomain $ImperionDomain) {
                $m | Add-Member -NotePropertyName '_imperionMailbox' -NotePropertyValue $mb -Force
                $kept.Add($m)
            }
        }
    }

    $map = [ordered]@{
        mailbox            = { param($m) Get-ImperionMember $m '_imperionMailbox' }
        subject            = 'subject'
        from_address       = { param($m) Get-ImperionPropertyPath -InputObject $m -Path 'from.emailAddress.address' }
        from_name          = { param($m) Get-ImperionPropertyPath -InputObject $m -Path 'from.emailAddress.name' }
        to_addresses       = { param($m) (@(Get-ImperionMember $m 'toRecipients') | Where-Object { $_ } | ForEach-Object { Get-ImperionPropertyPath -InputObject $_ -Path 'emailAddress.address' }) | Join-ImperionValues }
        cc_addresses       = { param($m) (@(Get-ImperionMember $m 'ccRecipients') | Where-Object { $_ } | ForEach-Object { Get-ImperionPropertyPath -InputObject $_ -Path 'emailAddress.address' }) | Join-ImperionValues }
        received_date_time = 'receivedDateTime'
        sent_date_time     = 'sentDateTime'
        conversation_id    = 'conversationId'
        has_attachments    = 'hasAttachments'
        importance         = 'importance'
        is_read            = 'isRead'
        web_link           = 'webLink'
    }

    $kept | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'm365_email' -TenantId $TenantId -ExternalIdProperty 'id'
}
