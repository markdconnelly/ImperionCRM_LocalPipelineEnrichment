function Get-ImperionMetaPostInsight {
    <#
    .SYNOPSIS
        Collect per-post / per-media organic insights and flatten them to meta_insights bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for the Meta source, slice H (#357; front-end Social
        plane epic #1338 / ADR-0124). Pulls post-level insight metrics for the Facebook Page
        posts (/{post-id}/insights, entity_kind 'post') and/or the Instagram media
        (/{media-id}/insights, entity_kind 'media') passed in. One flat row per (entity,
        metric, period, value point); external_id =
        "<entity_kind>:<entity_id>:<metric>:<period>:<end_time>"; source 'meta'. Target: bronze
        meta_insights (front-end migration 0075) → silver social_metric via
        Invoke-ImperionSocialMetricMerge, which NORMALIZES the raw metric names (#135). Returns
        rows; does not write. Requires Initialize-ImperionContext.

        Takes post/media ids from the pipeline (the rows Get-ImperionMetaPagePost /
        Get-ImperionInstagramMedia emit bind by their external_id property) or explicit ids.

        METRIC DEPRECATION TOLERANCE (the Get-ImperionMetaInsight precedent, #100): metrics are
        requested ONE AT A TIME per entity, so a deprecated metric logs a warning and the run
        continues; it never aborts. Trim retired names from -PostMetric / -MediaMetric as Meta
        retires them. ASSUMED-FIELD-NAMES caveat: defaults follow the v23.0 post/media insights
        reference; verify against a live first run.
    .PARAMETER PostId
        Facebook post ids (entity_kind 'post'). Accepts pipeline input (binds external_id).
    .PARAMETER MediaId
        Instagram media ids (entity_kind 'media').
    .PARAMETER PostMetric
        Post-level metrics requested for each post.
    .PARAMETER MediaMetric
        Media-level metrics requested for each IG media item.
    .PARAMETER Period
        Insights period. Default 'lifetime' (post/media insights are cumulative-to-date).
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant.
    .PARAMETER Token
        Meta system-user / page token override. Defaults to the SecretStore resolution (ADR-0013).
    .EXAMPLE
        Get-ImperionMetaPagePost -PageId $pageId -Token $t | Get-ImperionMetaPostInsight -Token $t | Set-ImperionMetaInsightToBronze
    .EXAMPLE
        Get-ImperionMetaPostInsight -MediaId 'media1','media2' -Token $t
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('external_id')][string[]] $PostId,
        [string[]] $MediaId,
        [string[]] $PostMetric = @('post_impressions', 'post_impressions_unique', 'post_engaged_users', 'post_clicks'),
        [string[]] $MediaMetric = @('reach', 'saved', 'total_interactions'),
        [string] $Period = 'lifetime',
        [string] $TenantId,
        [string] $Token
    )

    begin {
        $cfg = Get-ImperionConfig
        if (-not $TenantId) { $TenantId = $cfg.LocalTenantId }
        $Token = Resolve-ImperionMetaToken -Token $Token

        $map = [ordered]@{
            entity_kind        = '_imperionEntityKind'
            entity_external_id = '_imperionEntityId'
            metric             = 'name'
            period             = 'period'
            end_time           = 'end_time'
            value              = 'value'
        }

        # One metric per request so a deprecated metric (#100) costs ONE warning, not the run.
        # $Period is passed in explicitly (not captured) so the analyzer sees it consumed.
        $collectEntityPoints = {
            param([string] $entityKind, [string] $entityId, [string[]] $metrics, [string] $metricPeriod)
            foreach ($metric in $metrics) {
                $uri = '{0}/insights?metric={1}&period={2}' -f [uri]::EscapeDataString($entityId), $metric, $metricPeriod
                try { $series = @(Invoke-ImperionMetaRequest -Token $Token -Uri $uri) }
                catch {
                    Write-ImperionLog -Level Warn -Source 'meta' `
                        -Message "Post insight metric '$metric' failed for $entityKind $entityId (deprecated?) - continuing: $($_.Exception.Message)"
                    continue
                }
                foreach ($insight in $series) {
                    $seriesName = [string](Get-ImperionMember $insight 'name')
                    $seriesPeriod = [string](Get-ImperionMember $insight 'period')
                    foreach ($point in @(Get-ImperionMember $insight 'values')) {
                        if ($null -eq $point) { continue }
                        $endTime = [string](Get-ImperionMember $point 'end_time')
                        # post/media lifetime insights often omit end_time — date to today (UTC).
                        if (-not $endTime) { $endTime = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd') }
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
    }

    process {
        $points = [System.Collections.Generic.List[object]]::new()
        foreach ($id in $PostId) {
            if (-not $id) { continue }
            foreach ($point in @(& $collectEntityPoints 'post' $id $PostMetric $Period)) { $points.Add($point) }
        }
        foreach ($id in $MediaId) {
            if (-not $id) { continue }
            foreach ($point in @(& $collectEntityPoints 'media' $id $MediaMetric $Period)) { $points.Add($point) }
        }
        $points | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'meta' -TenantId $TenantId -ExternalIdProperty '_imperionExternalId'
    }
}
