function Invoke-ImperionAzureInventorySync {
    <#
    .SYNOPSIS
        Inventory Azure (management groups, subscriptions, resource groups, resources) and Microsoft Sentinel objects into Postgres bronze.
    .DESCRIPTION
        Change detection is built into the upsert ("check for updates; if nothing changed,
        move on"). Sentinel objects are queried only for Log Analytics workspaces that have
        Sentinel; a workspace without it logs zero and is skipped. Requires Initialize-ImperionContext.
    .PARAMETER ApiVersionResources
        ARM api-version for resource/RG listing (override if your tenant needs a different one).
    .EXAMPLE
        Invoke-ImperionAzureInventorySync
    #>
    [CmdletBinding()]
    param(
        [string] $ApiVersionResources = '2022-09-01'
    )

    $cfg = Get-ImperionConfig
    $tenantId = $cfg.LocalTenantId
    $started = Get-Date
    $armToken = Get-ImperionArmToken
    $conn = New-ImperionDbConnection

    function Save-Inventory {
        param($Items, [System.Collections.IDictionary] $Map, [string] $Source, [string] $Table, [string] $ExternalIdProperty = 'id')
        if (-not $Items -or @($Items).Count -eq 0) { Write-ImperionLog -Source $Source -Message "${Table}: 0 items."; return }
        $flat = $Items | ConvertTo-ImperionFlatObject -PropertyMap $Map -Source $Source -TenantId $tenantId -ExternalIdProperty $ExternalIdProperty
        $tally = Invoke-ImperionBronzeUpsert -Connection $conn -Table $Table -Rows $flat
        Write-ImperionLog -Level Metric -Source $Source -Message "$Table synced." -Data @{ scanned = $tally.scanned; inserted = $tally.inserted; updated = $tally.updated; unchanged = $tally.unchanged }
    }

    $joinTags = { param($tags) if ($tags) { ($tags.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join '; ' } }
    $rgFromId = { param($id) if ($id -match '/resourceGroups/([^/]+)') { $Matches[1] } }

    try {
        $mgmtGroups = Invoke-ImperionArmRequest -Path '/providers/Microsoft.Management/managementGroups?api-version=2021-04-01' -AccessToken $armToken
        Save-Inventory -Items $mgmtGroups -Source 'azure' -Table 'azure_management_groups' -Map ([ordered]@{
            name = 'name'; display_name = 'properties.displayName'; mg_tenant_id = 'properties.tenantId'
        })

        $subscriptions = Invoke-ImperionArmRequest -Path '/subscriptions?api-version=2022-12-01' -AccessToken $armToken
        Save-Inventory -Items $subscriptions -Source 'azure' -Table 'azure_subscriptions' -ExternalIdProperty 'subscriptionId' -Map ([ordered]@{
            display_name = 'displayName'; state = 'state'; sub_tenant_id = 'tenantId'
        })

        foreach ($sub in $subscriptions) {
            $subId = $sub.subscriptionId
            Write-ImperionLog -Source 'azure' -Message "Subscription $($sub.displayName) ($subId)…"

            $resourceGroups = Invoke-ImperionArmRequest -Path "/subscriptions/$subId/resourcegroups?api-version=$ApiVersionResources" -AccessToken $armToken
            Save-Inventory -Items $resourceGroups -Source 'azure' -Table 'azure_resource_groups' -Map ([ordered]@{
                name = 'name'; location = 'location'; subscription_id = { $subId }; provisioning_state = 'properties.provisioningState'; tags = { param($x) & $joinTags (Get-ImperionMember $x 'tags') }
            })

            $resources = Invoke-ImperionArmRequest -Path "/subscriptions/$subId/resources?api-version=$ApiVersionResources" -AccessToken $armToken
            Save-Inventory -Items $resources -Source 'azure' -Table 'azure_resources' -Map ([ordered]@{
                name = 'name'; type = 'type'; location = 'location'; resource_group = { param($x) & $rgFromId (Get-ImperionMember $x 'id') }; subscription_id = { $subId }; sku = 'sku.name'; kind = 'kind'; tags = { param($x) & $joinTags (Get-ImperionMember $x 'tags') }
            })

            $workspaces = Invoke-ImperionArmRequest -Path "/subscriptions/$subId/providers/Microsoft.OperationalInsights/workspaces?api-version=2022-10-01" -AccessToken $armToken
            foreach ($ws in $workspaces) {
                $wsRg = & $rgFromId (Get-ImperionMember $ws 'id')
                $sentinelBase = "/subscriptions/$subId/resourceGroups/$wsRg/providers/Microsoft.OperationalInsights/workspaces/$($ws.name)/providers/Microsoft.SecurityInsights"
                try {
                    $alertRules = Invoke-ImperionArmRequest -Path "$sentinelBase/alertRules?api-version=2023-11-01" -AccessToken $armToken
                }
                catch {
                    Write-ImperionLog -Source 'sentinel' -Message "Workspace $($ws.name): no Sentinel (skipping). $($_.Exception.Message)"
                    continue
                }
                Save-Inventory -Items $alertRules -Source 'sentinel' -Table 'sentinel_analytic_rules' -Map ([ordered]@{
                    name = 'name'; display_name = 'properties.displayName'; rule_kind = 'kind'; enabled = 'properties.enabled'; severity = 'properties.severity'; tactics = { param($x) (Get-ImperionPropertyPath -InputObject $x -Path 'properties.tactics') | Join-ImperionValues }; last_modified = 'properties.lastModifiedUtc'; workspace = { $ws.name }
                })
                $automationRules = Invoke-ImperionArmRequest -Path "$sentinelBase/automationRules?api-version=2023-11-01" -AccessToken $armToken
                Save-Inventory -Items $automationRules -Source 'sentinel' -Table 'sentinel_automation_rules' -Map ([ordered]@{
                    display_name = 'properties.displayName'; rule_order = 'properties.order'; workspace = { $ws.name }
                })
                $watchlists = Invoke-ImperionArmRequest -Path "$sentinelBase/watchlists?api-version=2023-11-01" -AccessToken $armToken
                Save-Inventory -Items $watchlists -Source 'sentinel' -Table 'sentinel_watchlists' -Map ([ordered]@{
                    display_name = 'properties.displayName'; provider = 'properties.provider'; ws_source = 'properties.source'; updated = 'properties.updated'; workspace = { $ws.name }
                })
            }

            try {
                $workbooks = Invoke-ImperionArmRequest -Path "/subscriptions/$subId/providers/Microsoft.Insights/workbooks?category=sentinel&api-version=2022-04-01" -AccessToken $armToken
                Save-Inventory -Items $workbooks -Source 'sentinel' -Table 'sentinel_workbooks' -Map ([ordered]@{
                    display_name = 'properties.displayName'; category = 'properties.category'; version = 'properties.version'; time_modified = 'properties.timeModified'; subscription_id = { $subId }
                })
            }
            catch {
                Write-ImperionLog -Level Warn -Source 'sentinel' -Message "Workbook query failed for ${subId}: $($_.Exception.Message)"
            }
        }
    }
    finally { $conn.Dispose() }

    Write-ImperionLog -Level Metric -Source 'azure' -Message 'Azure + Sentinel inventory complete.' -Data @{ subscriptions = @($subscriptions).Count; seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 1) }
}
