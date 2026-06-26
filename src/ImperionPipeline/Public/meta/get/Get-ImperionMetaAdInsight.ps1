function Get-ImperionMetaAdInsight {
    <#
    .SYNOPSIS
        Collect Meta paid ad / campaign insights and flatten them to meta_insights bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for the Meta paid plane, slice H (#357; front-end
        Social plane epic #1338 / ADR-0124 decision 6). Pulls Marketing API insights from the
        ad account (GET /act_{ad-account-id}/insights) at the requested -Level (ad | campaign),
        for the requested -DatePreset window. Unlike organic insights (a {values:[…]} series),
        ad insights arrive as ONE flat object per entity with each metric as a numeric FIELD;
        this collector pivots every requested metric field into its own meta_insights row so the
        paid metrics share the organic envelope and merge through the SAME normalized
        social_metric path (Invoke-ImperionSocialMetricMerge, #135).

        One flat row per (entity, metric, period, day); entity_kind = -Level ('ad' or
        'campaign'); entity_external_id = the ad/campaign id; period = -DatePreset; end_time =
        the insight row's date_stop (else today UTC); external_id =
        "<entity_kind>:<entity_id>:<metric>:<period>:<end_time>"; source 'meta'. Target: bronze
        meta_insights (front-end migration 0075) → silver social_metric (platform 'meta_ads')
        via Invoke-ImperionSocialMetricMerge. Returns rows; does not write. Requires
        Initialize-ImperionContext.

        The ad-account id is resolved from -AdAccountId, else the IMPERION_META_AD_ACCOUNT_ID
        env var (the act_ prefix is added if absent). With no ad account configured the
        collector returns nothing (the paid plane is OPTIONAL — fail-soft, no throw), so a Page
        with no ad spend never breaks the metric task. ASSUMED-FIELD-NAMES caveat: defaults
        follow the v23.0 Marketing API insights reference; verify against a live first run.
    .PARAMETER AdAccountId
        Ad account id (with or without the act_ prefix). Defaults to IMPERION_META_AD_ACCOUNT_ID.
    .PARAMETER Level
        Aggregation level → entity_kind. 'ad' or 'campaign'. Default 'campaign'.
    .PARAMETER Metric
        Insight metric fields to pivot into rows.
    .PARAMETER DatePreset
        Marketing API date_preset window → the period label. Default 'last_30d'.
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant.
    .PARAMETER Token
        Meta system-user token override. Defaults to the SecretStore resolution (ADR-0013).
    .PARAMETER MaxPages
        Paging cap forwarded to the connect layer. Default 100.
    .EXAMPLE
        Get-ImperionMetaAdInsight -AdAccountId 'act_123' -Level campaign | Set-ImperionMetaInsightToBronze
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $AdAccountId,
        [ValidateSet('ad', 'campaign')][string] $Level = 'campaign',
        [string[]] $Metric = @('spend', 'impressions', 'reach', 'clicks', 'ctr', 'cpc', 'cpm', 'frequency'),
        [string] $DatePreset = 'last_30d',
        [string] $TenantId,
        [string] $Token,
        [int] $MaxPages = 100
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }

    if (-not $AdAccountId) { $AdAccountId = $env:IMPERION_META_AD_ACCOUNT_ID }
    if (-not $AdAccountId) {
        Write-ImperionLog -Level Warn -Source 'meta' -Message 'meta ad insights skipped: no ad account (set IMPERION_META_AD_ACCOUNT_ID).'
        return
    }
    if ($AdAccountId -notmatch '^act_') { $AdAccountId = "act_$AdAccountId" }

    $Token = Resolve-ImperionMetaToken -Token $Token

    # The id field identifies the entity at this level; request it alongside the metrics + dates.
    $idField = if ($Level -eq 'ad') { 'ad_id' } else { 'campaign_id' }
    $fields = (@($idField) + $Metric + @('date_start', 'date_stop')) -join ','
    $uri = '{0}/insights?level={1}&date_preset={2}&fields={3}&limit=100' -f `
        [uri]::EscapeDataString($AdAccountId), $Level, $DatePreset, $fields

    $rows = @(Invoke-ImperionMetaRequest -Token $Token -Uri $uri -MaxPages $MaxPages)

    $map = [ordered]@{
        entity_kind        = '_imperionEntityKind'
        entity_external_id = '_imperionEntityId'
        metric             = 'name'
        period             = 'period'
        end_time           = 'end_time'
        value              = 'value'
    }

    $points = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $rows) {
        if ($null -eq $row) { continue }
        $entityId = [string](Get-ImperionMember $row $idField)
        if (-not $entityId) { continue }
        $dateStop = [string](Get-ImperionMember $row 'date_stop')
        if (-not $dateStop) { $dateStop = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd') }
        foreach ($metricName in $Metric) {
            $value = Get-ImperionMember $row $metricName
            if ($null -eq $value) { continue }   # metric not present for this entity → skip
            $points.Add([pscustomobject]@{
                    name                = $metricName
                    period              = $DatePreset
                    end_time            = $dateStop
                    value               = $value
                    _imperionEntityKind = $Level
                    _imperionEntityId   = $entityId
                    _imperionExternalId = ('{0}:{1}:{2}:{3}:{4}' -f $Level, $entityId, $metricName, $DatePreset, $dateStop)
                })
        }
    }

    $points | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'meta' -TenantId $TenantId -ExternalIdProperty '_imperionExternalId'
}
