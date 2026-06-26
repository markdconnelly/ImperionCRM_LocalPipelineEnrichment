function Get-ImperionThreadsInsight {
    <#
    .SYNOPSIS
        Collect Threads profile + per-post organic insights and flatten them to threads_insights bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for the `threads` source (LocalPipeline #356,
        front-end Threads epic #1334 / ADR-0125). Pulls profile (user-level) organic insight
        metrics (`/{threads-user-id}/threads_insights`) plus per-post insights for each post
        id piped in (`/{thread-id}/insights`). One flat row per (entity, metric, period,
        value point); external_id = "<entity_kind>:<entity_id>:<metric>:<period>:<end_time>";
        entity_kind is 'profile' or 'post'; source 'threads'. Target: bronze `threads_insights`
        (front-end migration 0208) → silver `social_metric` (platform `threads`) via
        Invoke-ImperionThreadsMerge. Returns rows; does not write. Requires
        Initialize-ImperionContext.

        METRIC DEPRECATION TOLERANCE (the Get-ImperionMetaInsight precedent): metrics are
        requested ONE AT A TIME so a single dead/unauthorized metric logs a warning and the
        run continues; it never aborts. The Threads insights `metric` parameter returns a
        `{name, period, total_value:{value}}` aggregate per metric (no values[] series for
        the lifetime/post aggregates) — the single point is dated to today (UTC) so one
        idempotent row lands per day. ASSUMED-FIELD-NAMES caveat: defaults follow the
        published Threads insights reference; trim retired names from -ProfileMetric /
        -PostMetric and verify against a live first run.
    .PARAMETER ThreadsUserId
        The Threads user id whose profile insights to pull. Defaults to the configured
        IMPERION_THREADS_USER_ID when omitted.
    .PARAMETER PostId
        Our Threads post ids to pull per-post insights for. Accepts pipeline input —
        including the flattened post rows themselves (binds external_id by property name).
    .PARAMETER ProfileMetric
        Profile (user-level) metrics. Defaults follow the published Threads reference.
    .PARAMETER PostMetric
        Per-post metrics requested for each -PostId.
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant.
    .PARAMETER Token
        Threads token override. Defaults to the credential-registry resolution
        (Resolve-ImperionThreadsToken, ADR-0103).
    .EXAMPLE
        Get-ImperionThreadsInsight -ThreadsUserId '178414...' | Set-ImperionThreadsInsightToBronze
    .EXAMPLE
        Get-ImperionThreadsPost | Get-ImperionThreadsInsight | Set-ImperionThreadsInsightToBronze
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $ThreadsUserId,
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('external_id')][string[]] $PostId,
        [string[]] $ProfileMetric = @('views', 'likes', 'replies', 'reposts', 'quotes', 'followers_count'),
        [string[]] $PostMetric = @('views', 'likes', 'replies', 'reposts', 'quotes'),
        [string] $TenantId,
        [string] $Token
    )

    begin {
        $cfg = Get-ImperionConfig
        if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }
        $Token = Resolve-ImperionThreadsToken -Token $Token -FailClosed
        if (-not $ThreadsUserId) { $ThreadsUserId = $env:IMPERION_THREADS_USER_ID }

        $map = [ordered]@{
            entity_kind        = '_imperionEntityKind'
            entity_external_id = '_imperionEntityId'
            metric             = 'name'
            period             = 'period'
            end_time           = 'end_time'
            value              = 'value'
        }

        # One metric per request so a deprecated/unauthorized metric costs ONE warning, not
        # the run (the Get-ImperionMetaInsight #100 precedent). Threads returns
        # {name, period, total_value:{value}} per metric; date the single point to today (UTC).
        $collectInsightPoints = {
            param([string] $entityKind, [string] $entityId, [string[]] $metrics, [string] $edge)
            foreach ($metric in $metrics) {
                $uri = '{0}/{1}?metric={2}' -f [uri]::EscapeDataString($entityId), $edge, $metric
                try { $series = @(Invoke-ImperionThreadsRequest -Token $Token -Uri $uri) }
                catch {
                    Write-ImperionLog -Level Warn -Source 'threads' `
                        -Message "Insight metric '$metric' failed for $entityKind $entityId (deprecated/unauthorized?) - continuing: $($_.Exception.Message)"
                    continue
                }
                foreach ($insight in $series) {
                    $seriesName = [string](Get-ImperionMember $insight 'name')
                    $seriesPeriod = [string](Get-ImperionMember $insight 'period')
                    $totalValue = Get-ImperionMember $insight 'total_value'
                    $aggregate = if ($null -ne $totalValue) { Get-ImperionMember $totalValue 'value' } else { Get-ImperionMember $insight 'value' }
                    if ($null -eq $aggregate) { continue }
                    $effectivePeriod = if ($seriesPeriod) { $seriesPeriod } else { 'lifetime' }
                    $endTime = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
                    [pscustomobject]@{
                        name                = $seriesName
                        period              = $effectivePeriod
                        end_time            = $endTime
                        value               = $aggregate
                        _imperionEntityKind = $entityKind
                        _imperionEntityId   = $entityId
                        _imperionExternalId = ('{0}:{1}:{2}:{3}:{4}' -f $entityKind, $entityId, $seriesName, $effectivePeriod, $endTime)
                    }
                }
            }
        }

        $points = [System.Collections.Generic.List[object]]::new()

        if ($ThreadsUserId) {
            foreach ($point in @(& $collectInsightPoints 'profile' $ThreadsUserId $ProfileMetric 'threads_insights')) {
                $points.Add($point)
            }
        }
    }
    process {
        foreach ($id in $PostId) {
            if (-not $id) { continue }
            foreach ($point in @(& $collectInsightPoints 'post' $id $PostMetric 'insights')) {
                $points.Add($point)
            }
        }
    }
    end {
        $points | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'threads' -TenantId $TenantId -ExternalIdProperty '_imperionExternalId'
    }
}
