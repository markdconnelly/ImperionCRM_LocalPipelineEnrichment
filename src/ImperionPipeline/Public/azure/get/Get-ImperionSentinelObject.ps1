function Get-ImperionSentinelObject {
    <#
    .SYNOPSIS
        Collect Microsoft Sentinel objects (analytic/automation rules, watchlists, workbooks) and flatten them to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) — the deferred "Sentinel get" (issue #97) that
        lets the per-entity get → post composition cover Sentinel. Multi-step by nature
        (mirrors Invoke-ImperionAzureInventorySync's traversal): ARM token (existing
        Azure RBAC Reader — no new grant) → enumerate subscriptions → Log Analytics
        workspaces → per workspace the Microsoft.SecurityInsights objects (analytic
        rules, automation rules, watchlists), plus per subscription the Sentinel-category
        workbooks. A workspace WITHOUT Sentinel yields a 4xx on its first query — logged
        and skipped, never an error (Sentinel rides on a workspace with the
        SecurityInsights solution).

        Returns one flat row stream for all four entity sets; each row carries an
        `entity` discriminator (analytic_rules / automation_rules / watchlists /
        workbooks) that Set-ImperionSentinelToBronze routes on (and projects away — the
        bronze tables have no such column). Flat columns mirror the migration-0038
        sentinel_* tables exactly. Returns rows; does not write. Requires
        Initialize-ImperionContext.
    .PARAMETER TenantId
        Tenant to authenticate against; defaults to the partner tenant.
    .PARAMETER SentinelApiVersion
        SecurityInsights api-version. Default 2023-11-01.
    .OUTPUTS
        Flat bronze rows (source 'sentinel') ready for Set-ImperionSentinelToBronze.
    .EXAMPLE
        Get-ImperionSentinelObject | Set-ImperionSentinelToBronze
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId,
        [string] $SentinelApiVersion = '2023-11-01'
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.LocalTenantId }

    $armToken = Get-ImperionArmToken -TenantId $TenantId
    $rows = [System.Collections.Generic.List[object]]::new()
    $rgFromId = { param($id) if ($id -match '/resourceGroups/([^/]+)') { $Matches[1] } }

    $subscriptions = Invoke-ImperionArmRequest -Path '/subscriptions?api-version=2022-12-01' -AccessToken $armToken
    foreach ($subscription in $subscriptions) {
        $subscriptionId = $subscription.subscriptionId

        $workspaces = Invoke-ImperionArmRequest -Path "/subscriptions/$subscriptionId/providers/Microsoft.OperationalInsights/workspaces?api-version=2022-10-01" -AccessToken $armToken
        foreach ($workspace in $workspaces) {
            $workspaceName = $workspace.name
            $workspaceResourceGroup = & $rgFromId (Get-ImperionMember $workspace 'id')
            $sentinelBase = "/subscriptions/$subscriptionId/resourceGroups/$workspaceResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights"

            try {
                $alertRules = Invoke-ImperionArmRequest -Path "$sentinelBase/alertRules?api-version=$SentinelApiVersion" -AccessToken $armToken
            }
            catch {
                Write-ImperionLog -Source 'sentinel' -Message "Workspace ${workspaceName}: no Sentinel (skipping). $($_.Exception.Message)"
                continue
            }
            $alertRules | ConvertTo-ImperionFlatObject -Source 'sentinel' -TenantId $TenantId -ExternalIdProperty 'id' -PropertyMap ([ordered]@{
                entity = { 'analytic_rules' }
                name = 'name'; display_name = 'properties.displayName'; rule_kind = 'kind'
                enabled = 'properties.enabled'; severity = 'properties.severity'
                tactics = { param($rule) (Get-ImperionPropertyPath -InputObject $rule -Path 'properties.tactics') | Join-ImperionValues }
                last_modified = 'properties.lastModifiedUtc'; workspace = { $workspaceName }
            }) | ForEach-Object { $rows.Add($_) }

            $automationRules = Invoke-ImperionArmRequest -Path "$sentinelBase/automationRules?api-version=$SentinelApiVersion" -AccessToken $armToken
            $automationRules | ConvertTo-ImperionFlatObject -Source 'sentinel' -TenantId $TenantId -ExternalIdProperty 'id' -PropertyMap ([ordered]@{
                entity = { 'automation_rules' }
                display_name = 'properties.displayName'; rule_order = 'properties.order'; workspace = { $workspaceName }
            }) | ForEach-Object { $rows.Add($_) }

            $watchlists = Invoke-ImperionArmRequest -Path "$sentinelBase/watchlists?api-version=$SentinelApiVersion" -AccessToken $armToken
            $watchlists | ConvertTo-ImperionFlatObject -Source 'sentinel' -TenantId $TenantId -ExternalIdProperty 'id' -PropertyMap ([ordered]@{
                entity = { 'watchlists' }
                display_name = 'properties.displayName'; provider = 'properties.provider'
                ws_source = 'properties.source'; updated = 'properties.updated'; workspace = { $workspaceName }
            }) | ForEach-Object { $rows.Add($_) }
        }

        try {
            $workbooks = Invoke-ImperionArmRequest -Path "/subscriptions/$subscriptionId/providers/Microsoft.Insights/workbooks?category=sentinel&api-version=2022-04-01" -AccessToken $armToken
            $workbooks | ConvertTo-ImperionFlatObject -Source 'sentinel' -TenantId $TenantId -ExternalIdProperty 'id' -PropertyMap ([ordered]@{
                entity = { 'workbooks' }
                display_name = 'properties.displayName'; category = 'properties.category'
                version = 'properties.version'; time_modified = 'properties.timeModified'
                subscription_id = { $subscriptionId }
            }) | ForEach-Object { $rows.Add($_) }
        }
        catch {
            Write-ImperionLog -Level Warn -Source 'sentinel' -Message "Workbook query failed for ${subscriptionId}: $($_.Exception.Message)"
        }
    }

    Write-ImperionLog -Source 'sentinel' -Message 'Sentinel objects collected.' -Data @{
        subscriptions = @($subscriptions).Count; rows = $rows.Count
    }
    return $rows.ToArray()
}
