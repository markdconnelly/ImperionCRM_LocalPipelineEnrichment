function Get-ImperionInstagramMedia {
    <#
    .SYNOPSIS
        Collect Instagram business-account media and flatten them to instagram_media bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for the Meta source, issue #126. Instagram
        business accounts are reached THROUGH the linked Facebook Page: the IG user id
        is resolved via GET /{PageId}?fields=instagram_business_account (override with
        -IgUserId to skip the hop), then /{ig-user-id}/media is paged and flattened to
        the instagram_media column set (front-end migration 0075; created_time <-
        timestamp). When the page has no linked IG account the collector warns and
        returns nothing — an unlinked IG is a configuration state, not an error.
        Returns rows; does not write. Requires Initialize-ImperionContext.

        ASSUMED-FIELD-NAMES caveat: fields follow Meta's published IG-media reference
        (instagram_basic scope); unreadable fields land NULL in flat columns and survive
        in raw_payload. Verify against a live first run.
    .PARAMETER PageId
        The linked Facebook Page id (used to resolve the IG user). Required unless
        -IgUserId is given.
    .PARAMETER IgUserId
        Instagram business-account (IG user) id override — skips the Page hop.
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant.
    .PARAMETER Token
        Meta system-user token override. Defaults to the SecretStore resolution (ADR-0013).
    .PARAMETER MaxPages
        Paging cap forwarded to the connect layer. Default 100.
    .EXAMPLE
        Get-ImperionInstagramMedia -PageId '123456789' | Set-ImperionInstagramMediaToBronze
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByPage')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByPage')][string] $PageId,
        [Parameter(Mandatory, ParameterSetName = 'ByIgUser')][string] $IgUserId,
        [string] $TenantId,
        [string] $Token,
        [int] $MaxPages = 100
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }
    $Token = Resolve-ImperionMetaToken -Token $Token

    if (-not $IgUserId) {
        $page = @(Invoke-ImperionMetaRequest -Token $Token `
                -Uri ('{0}?fields=instagram_business_account' -f [uri]::EscapeDataString($PageId))) |
            Select-Object -First 1
        $IgUserId = if ($null -ne $page) {
            [string](Get-ImperionPropertyPath -InputObject $page -Path 'instagram_business_account.id')
        }
        if (-not $IgUserId) {
            Write-ImperionLog -Level Warn -Source 'meta' -Message "Page $PageId has no linked instagram_business_account - skipping IG media."
            return
        }
    }

    $fields = 'caption,media_type,media_product_type,permalink,media_url,timestamp,like_count,comments_count,username'
    $uri = '{0}/media?fields={1}&limit=100' -f [uri]::EscapeDataString($IgUserId), $fields
    $media = @(Invoke-ImperionMetaRequest -Token $Token -Uri $uri -MaxPages $MaxPages)
    foreach ($item in $media) {
        $item | Add-Member -NotePropertyName '_imperionIgUserId' -NotePropertyValue $IgUserId -Force
    }

    $map = [ordered]@{
        ig_user_id         = '_imperionIgUserId'
        ig_username        = 'username'
        caption            = 'caption'
        media_type         = 'media_type'
        media_product_type = 'media_product_type'
        permalink          = 'permalink'
        media_url          = 'media_url'
        created_time       = 'timestamp'
        like_count         = 'like_count'
        comments_count     = 'comments_count'
    }

    $media | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'instagram' -TenantId $TenantId -ExternalIdProperty 'id'
}
