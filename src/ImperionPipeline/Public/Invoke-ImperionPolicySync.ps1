function Invoke-ImperionPolicySync {
    <#
    .SYNOPSIS
        Pull the current state of security-posture policies into Postgres bronze and report drift against golden states.
    .DESCRIPTION
        Read-only (Policy.Read.All, DeviceManagementConfiguration.Read.All,
        DeviceManagementServiceConfig.Read.All). Pulls Conditional Access, Intune security
        (settings-catalog / endpoint security), device configuration, Autopilot, and Defender
        XDR endpoint-security policies; flattens and upserts each to its observed bronze table
        with change detection; then compares each observed policy to its golden state and logs
        drift. Defender vs. Intune-security split is by endpoint-security template family
        (flagged as an assumption — docs/integrations/security-posture-policies.md). Requires
        Initialize-ImperionContext.
    .PARAMETER TenantId
        Tenant to poll; defaults to the partner tenant (GDAP for customer tenants).
    .EXAMPLE
        Invoke-ImperionPolicySync
    #>
    [CmdletBinding()]
    param([string] $TenantId)

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }
    $started = Get-Date
    $graph = Get-ImperionGraphToken -TenantId $TenantId
    $conn = New-ImperionDbConnection

    function Save-Policy {
        param($Items, [System.Collections.IDictionary] $Map, [string] $Source, [string] $Table)
        if (-not $Items -or @($Items).Count -eq 0) { Write-ImperionLog -Source $Source -Message "${Table}: 0 items."; return }
        $flat = $Items | ConvertTo-ImperionFlatObject -PropertyMap $Map -Source $Source -TenantId $TenantId -ExternalIdProperty 'id'
        $tally = Invoke-ImperionBronzeUpsert -Connection $conn -Table $Table -Rows $flat
        Write-ImperionLog -Level Metric -Source $Source -Message "$Table synced." -Data @{ scanned = $tally.scanned; inserted = $tally.inserted; updated = $tally.updated; unchanged = $tally.unchanged }
    }

    try {
        # 1. Conditional Access
        $ca = Invoke-ImperionGraphRequest -Uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies' -AccessToken $graph
        Save-Policy -Items $ca -Source 'm365' -Table 'entra_conditional_access_policies' -Map ([ordered]@{
            policy_name = 'displayName'; state = 'state'; created_date_time = 'createdDateTime'; modified_date_time = 'modifiedDateTime'
        })

        # 2. Device configuration profiles
        $deviceConfig = Invoke-ImperionGraphRequest -Uri 'https://graph.microsoft.com/v1.0/deviceManagement/deviceConfigurations' -AccessToken $graph
        Save-Policy -Items $deviceConfig -Source 'intune' -Table 'device_configuration_policies' -Map ([ordered]@{
            policy_name = 'displayName'; odata_type = '@odata.type'; created_date_time = 'createdDateTime'; modified_date_time = 'lastModifiedDateTime'
        })

        # 3. Autopilot deployment profiles
        $autopilot = Invoke-ImperionGraphRequest -Uri 'https://graph.microsoft.com/v1.0/deviceManagement/windowsAutopilotDeploymentProfiles' -AccessToken $graph
        Save-Policy -Items $autopilot -Source 'intune' -Table 'autopilot_policies' -Map ([ordered]@{
            policy_name = 'displayName'; locale = 'locale'; created_date_time = 'createdDateTime'; modified_date_time = 'lastModifiedDateTime'
        })

        # 4. Settings-catalog / endpoint-security policies (beta) → split Intune-security vs Defender XDR by template family.
        $configPolicies = Invoke-ImperionGraphRequest -Uri 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies' -AccessToken $graph
        $defenderFamilies = @('endpointSecurityAntivirus', 'endpointSecurityEndpointDetectionAndResponse', 'endpointSecurityFirewall', 'endpointSecurityAttackSurfaceReductionRules')
        $isDefender = { param($p) $fam = $p.templateReference.templateFamily; $fam -and ($defenderFamilies -contains $fam) }
        $defenderPolicies = @($configPolicies | Where-Object { & $isDefender $_ })
        $intuneSecurity = @($configPolicies | Where-Object { -not (& $isDefender $_) })

        $configMap = [ordered]@{
            policy_name        = 'name'
            template_family    = 'templateReference.templateFamily'
            technologies       = 'technologies'
            platforms          = 'platforms'
            modified_date_time = 'lastModifiedDateTime'
        }
        Save-Policy -Items $intuneSecurity   -Source 'intune'   -Table 'intune_security_policies'        -Map $configMap
        Save-Policy -Items $defenderPolicies  -Source 'defender' -Table 'defender_xdr_security_policies'   -Map $configMap

        # 5. Drift against golden states (logs a summary per type).
        $drift = Get-ImperionPolicyDrift -Connection $conn -TenantId $TenantId
        $byStatus = $drift | Group-Object status | ForEach-Object { "$($_.Name)=$($_.Count)" }
        Write-ImperionLog -Level Metric -Source 'policy' -Message 'Policy drift evaluated.' -Data @{ summary = ($byStatus -join ' ') }
    }
    finally { $conn.Dispose() }

    Write-ImperionLog -Level Metric -Source 'policy' -Message 'Policy sync complete.' -Data @{ tenant = $TenantId; seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 1) }
}
