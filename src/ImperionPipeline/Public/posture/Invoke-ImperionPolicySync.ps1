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
        (flagged as an assumption — docs/integrations/security-posture-policies.md).

        Per-client security posture (ADR-0126): fans out over EVERY mapped client tenant via
        Invoke-ImperionM365EstateSweep — the same registry-driven (account_tenant join an active
        m365 connection), per-tenant fail-isolated sweep the directory collectors already use
        (#358/#266) — instead of the home tenant only. A tenant with no consent/credential is
        skipped (Warn) and never blocks the rest. Idempotent (change-detected upsert). Requires
        Initialize-ImperionContext.
    .PARAMETER TenantId
        Pins the sweep to one tenant (the tenant-outer driver, #359); omit for the registry-driven
        estate fan-out (#358). Customer tenants are reached via the per-client onboarding app (§3).
    .EXAMPLE
        Invoke-ImperionPolicySync
    #>
    [CmdletBinding()]
    param([string] $TenantId)

    # Fan out over the mapped client tenants (ADR-0126); -TenantId pins one (#359). The original
    # single-tenant body runs verbatim per tenant inside the fail-isolated sweep (#358/#266).
    $sweep = @{}
    if ($PSBoundParameters.ContainsKey('TenantId')) { $sweep.TenantId = $TenantId }
    Invoke-ImperionM365EstateSweep @sweep -Source 'm365' -Label 'M365 security-posture policies' -PerTenant {
        param($TenantId)
        Invoke-ImperionPolicySyncForTenant -TenantId $TenantId
    }
}

function Invoke-ImperionPolicySyncForTenant {
    <#
    .SYNOPSIS
        Pull + drift-check one tenant's security-posture policies (the single-tenant body).
    .DESCRIPTION
        The single-tenant body behind Invoke-ImperionPolicySync — split out so the public cmdlet can
        fan it out per mapped client tenant via Invoke-ImperionM365EstateSweep (ADR-0126). A $null
        -TenantId falls back to the partner tenant (dormant-safe). Requires Initialize-ImperionContext.
    .PARAMETER TenantId
        Tenant to poll; $null/empty falls back to the partner tenant.
    #>
    [CmdletBinding()]
    param([string] $TenantId)

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.LocalTenantId }
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
            policy_name = 'displayName'; odata_type = { param($p) Get-ImperionMember $p '@odata.type' }; created_date_time = 'createdDateTime'; modified_date_time = 'lastModifiedDateTime'
        })

        # 3. Autopilot deployment profiles
        $autopilot = Invoke-ImperionGraphRequest -Uri 'https://graph.microsoft.com/v1.0/deviceManagement/windowsAutopilotDeploymentProfiles' -AccessToken $graph
        Save-Policy -Items $autopilot -Source 'intune' -Table 'autopilot_policies' -Map ([ordered]@{
            policy_name = 'displayName'; locale = 'locale'; created_date_time = 'createdDateTime'; modified_date_time = 'lastModifiedDateTime'
        })

        # 4. Settings-catalog / endpoint-security policies (beta) → split Intune-security vs Defender XDR by template family.
        $configPolicies = Invoke-ImperionGraphRequest -Uri 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies' -AccessToken $graph
        $defenderFamilies = @('endpointSecurityAntivirus', 'endpointSecurityEndpointDetectionAndResponse', 'endpointSecurityFirewall', 'endpointSecurityAttackSurfaceReductionRules')
        $isDefender = { param($p) $fam = Get-ImperionPropertyPath -InputObject $p -Path 'templateReference.templateFamily'; $fam -and ($defenderFamilies -contains $fam) }
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
