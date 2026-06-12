function Get-ImperionMetaInsight {
    <#
    .SYNOPSIS
        Collect Page + Instagram organic insights and flatten them to meta_insights bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for the Meta source, issue #126. Pulls daily
        organic insight metrics for the Facebook Page (/{PageId}/insights) and/or the
        Instagram business account (/{ig-user-id}/insights, resolved through the page
        when -IgUserId is omitted), plus an IG followers_count 'lifetime' snapshot row
        (GET /{ig-user-id}?fields=followers_count). One flat row per (entity, metric,
        period, value point); external_id =
        "<entity_kind>:<entity_id>:<metric>:<period>:<end_time>"; entity_kind is
        'page' or 'ig_user'; source 'meta'. Target: bronze `meta_insights` (front-end
        migration 0075) → silver `social_metric` via Invoke-ImperionMetaMerge.
        Returns rows; does not write. Requires Initialize-ImperionContext.

        METRIC DEPRECATION TOLERANCE: Meta deprecates insight metrics often and a
        request listing one dead metric fails WHOLE (#100). Metrics are therefore
        requested ONE AT A TIME — a failing metric logs a warning and the run
        continues; it never aborts. Trim retired names from -PageMetric/-IgMetric as
        Meta retires them. ASSUMED-FIELD-NAMES caveat: defaults follow the v23.0
        insights reference; verify against a live first run.
    .PARAMETER PageId
        Facebook Page id to pull page insights for (and to resolve the IG user from).
    .PARAMETER IgUserId
        Instagram business-account id override — skips the Page hop. IG insights are
        skipped when neither this resolves nor a linked account exists.
    .PARAMETER PageMetric
        Page metrics requested at period=day.
    .PARAMETER IgMetric
        IG-user metrics requested at period=day.
    .PARAMETER Period
        Insights period for the metric series. Default 'day'.
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant.
    .PARAMETER Token
        Meta system-user token override. Defaults to the SecretStore resolution (ADR-0013).
    .EXAMPLE
        Get-ImperionMetaInsight -PageId '123456789' | Set-ImperionMetaInsightToBronze
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $PageId,
        [string] $IgUserId,
        [string[]] $PageMetric = @('page_impressions', 'page_impressions_unique', 'page_post_engagements', 'page_fans', 'page_views_total'),
        [string[]] $IgMetric = @('reach', 'profile_views', 'accounts_engaged'),
        [string] $Period = 'day',
        [string] $TenantId,
        [string] $Token
    )

    if (-not $PageId -and -not $IgUserId) {
        throw 'Get-ImperionMetaInsight needs -PageId and/or -IgUserId.'
    }

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }
    $Token = Resolve-ImperionMetaToken -Token $Token

    # One metric per request so a deprecated metric (#100) costs ONE warning, not the run.
    $collectInsightPoints = {
        param([string] $entityKind, [string] $entityId, [string[]] $metrics, [string] $metricPeriod)
        foreach ($metric in $metrics) {
            $uri = '{0}/insights?metric={1}&period={2}' -f [uri]::EscapeDataString($entityId), $metric, $metricPeriod
            try { $series = @(Invoke-ImperionMetaRequest -Token $Token -Uri $uri) }
            catch {
                Write-ImperionLog -Level Warn -Source 'meta' `
                    -Message "Insight metric '$metric' failed for $entityKind $entityId (deprecated?) - continuing: $($_.Exception.Message)"
                continue
            }
            foreach ($insight in $series) {
                $seriesName = [string](Get-ImperionMember $insight 'name')
                $seriesPeriod = [string](Get-ImperionMember $insight 'period')
                foreach ($point in @(Get-ImperionMember $insight 'values')) {
                    if ($null -eq $point) { continue }
                    $endTime = [string](Get-ImperionMember $point 'end_time')
                    [pscustomobject]@{
                        name                = $seriesName
                        period              = $seriesPeriod
                        end_time            = $endTime
                        value               = Get-ImperionMember $point 'value'
                        _imperionEntityKind = $entityKind
                        _imperionEntityId   = $entityId
                        _imperionExternalId = ('{0}:{1}:{2}:{3}:{4}' -f $entityKind, $entityId, $seriesName, $seriesPeriod, $endTime)
                    }
                }
            }
        }
    }

    $points = [System.Collections.Generic.List[object]]::new()

    if ($PageId) {
        foreach ($point in @(& $collectInsightPoints 'page' $PageId $PageMetric $Period)) { $points.Add($point) }

        if (-not $IgUserId) {
            $page = @(Invoke-ImperionMetaRequest -Token $Token `
                    -Uri ('{0}?fields=instagram_business_account' -f [uri]::EscapeDataString($PageId))) |
                Select-Object -First 1
            $IgUserId = if ($null -ne $page) {
                [string](Get-ImperionPropertyPath -InputObject $page -Path 'instagram_business_account.id')
            }
        }
    }

    if ($IgUserId) {
        foreach ($point in @(& $collectInsightPoints 'ig_user' $IgUserId $IgMetric $Period)) { $points.Add($point) }

        # followers_count is not an insights metric — snapshot it as a 'lifetime' row,
        # dated so one row lands per day (idempotent external_id).
        try {
            $igUser = @(Invoke-ImperionMetaRequest -Token $Token `
                    -Uri ('{0}?fields=followers_count' -f [uri]::EscapeDataString($IgUserId))) |
                Select-Object -First 1
            $followers = Get-ImperionMember $igUser 'followers_count'
            if ($null -ne $followers) {
                $snapshotDate = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
                $points.Add([pscustomobject]@{
                        name                = 'followers_count'
                        period              = 'lifetime'
                        end_time            = $snapshotDate
                        value               = $followers
                        _imperionEntityKind = 'ig_user'
                        _imperionEntityId   = $IgUserId
                        _imperionExternalId = ('ig_user:{0}:followers_count:lifetime:{1}' -f $IgUserId, $snapshotDate)
                    })
            }
        }
        catch {
            Write-ImperionLog -Level Warn -Source 'meta' `
                -Message "followers_count snapshot failed for ig_user $IgUserId - continuing: $($_.Exception.Message)"
        }
    }

    $map = [ordered]@{
        entity_kind        = '_imperionEntityKind'
        entity_external_id = '_imperionEntityId'
        metric             = 'name'
        period             = 'period'
        end_time           = 'end_time'
        value              = 'value'
    }
    $points | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'meta' -TenantId $TenantId -ExternalIdProperty '_imperionExternalId'
}
