function Get-ImperionThreadsMention {
    <#
    .SYNOPSIS
        Collect public Threads mentions OF us and flatten them to threads_mentions bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for the `threads` source (LocalPipeline #356,
        front-end Threads epic #1334 / ADR-0125). Pages `/me/mentions` via the connect layer
        (bearer-header auth; never a querystring token) — the posts in which our Threads
        presence is @-mentioned. Target: bronze `threads_mentions` (front-end migration 0208)
        → silver `interaction` (source `threads`, kind `mention`, direction inbound) via
        Invoke-ImperionThreadsMerge (local merge ownership, ADR-0026). v1 mentions are *of us*
        so they ride the contact-centric timeline (ADR-0124 inbound-split D2; anonymous public
        brand chatter would route to the Social Engagement store, out of scope here). Returns
        rows; does not write. Requires Initialize-ImperionContext.

        ASSUMED-FIELD-NAMES caveat (the Get-ImperionMetaPagePost precedent): the field list
        follows the published Threads mentions reference; anything the token cannot read lands
        NULL in the flat column and survives in raw_payload. Verify against a live first run.
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant.
    .PARAMETER Since
        Optional incremental lower bound (ISO-8601 or unix time, passed as the documented
        `since` filter). Omit for a full backfill.
    .PARAMETER Token
        Threads token override. Defaults to the credential-registry resolution
        (Resolve-ImperionThreadsToken, ADR-0103).
    .PARAMETER MaxPages
        Paging cap forwarded to the connect layer. Default 100.
    .EXAMPLE
        Get-ImperionThreadsMention | Set-ImperionThreadsMentionToBronze
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId,
        [string] $Since,
        [string] $Token,
        [int] $MaxPages = 100
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }
    $Token = Resolve-ImperionThreadsToken -Token $Token -FailClosed

    $fields = 'id,username,text,permalink,timestamp,owner'
    $uri = 'me/mentions?fields={0}&limit=100' -f $fields
    if ($Since) { $uri += '&since=' + [uri]::EscapeDataString($Since) }

    $mentions = @(Invoke-ImperionThreadsRequest -Token $Token -Uri $uri -MaxPages $MaxPages)

    $map = [ordered]@{
        mentioned_post_external_id = 'id'
        threads_user_id            = 'owner.id'
        username                   = 'username'
        text_content               = 'text'
        permalink                  = 'permalink'
        created_time               = 'timestamp'
    }

    $mentions | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'threads' -TenantId $TenantId -ExternalIdProperty 'id'
}
