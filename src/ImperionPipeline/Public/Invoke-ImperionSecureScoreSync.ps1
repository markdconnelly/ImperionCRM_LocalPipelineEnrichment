function Invoke-ImperionSecureScoreSync {
    <#
    .SYNOPSIS
        Poll Microsoft Secure Score (overall snapshots) and Secure Score control profiles (the attributes) into Postgres bronze.
    .DESCRIPTION
        GET /security/secureScores gives daily overall-score snapshots (each with a per-control
        breakdown kept in raw_payload); GET /security/secureScoreControlProfiles gives the
        control-level attributes (category, title, max score, remediation, threats, user
        impact, implementation cost, tier). Read-only (SecurityEvents.Read.All). Change
        detection on the upsert. Requires Initialize-ImperionContext.
    .PARAMETER TenantId
        Tenant to poll; defaults to the partner tenant (GDAP for customer tenants).
    .EXAMPLE
        Invoke-ImperionSecureScoreSync
    #>
    [CmdletBinding()]
    param([string] $TenantId)

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }
    $started = Get-Date
    $graphToken = Get-ImperionGraphToken -TenantId $TenantId
    $conn = New-ImperionDbConnection

    try {
        # 1. Overall secure-score snapshots.
        $scores = Invoke-ImperionGraphRequest -Uri 'https://graph.microsoft.com/v1.0/security/secureScores' -AccessToken $graphToken
        $scoreMap = [ordered]@{
            current_score        = 'currentScore'
            max_score            = 'maxScore'
            active_user_count    = 'activeUserCount'
            licensed_user_count  = 'licensedUserCount'
            enabled_services     = { param($s) $s.enabledServices | Join-ImperionValues }
            created_date_time    = 'createdDateTime'
            azure_tenant_id      = 'azureTenantId'
        }
        $scoreRows = $scores | ConvertTo-ImperionFlatObject -PropertyMap $scoreMap -Source 'securescore' -TenantId $TenantId -ExternalIdProperty 'id'
        $t1 = if ($scoreRows) { Invoke-ImperionBronzeUpsert -Connection $conn -Table 'secure_scores' -Rows $scoreRows } else { [pscustomobject]@{ scanned = 0; inserted = 0; updated = 0; unchanged = 0 } }
        Write-ImperionLog -Level Metric -Source 'securescore' -Message 'secure_scores synced.' -Data @{ scanned = $t1.scanned; inserted = $t1.inserted; updated = $t1.updated; unchanged = $t1.unchanged }

        # 2. Control profiles — the secure-score attributes.
        $profiles = Invoke-ImperionGraphRequest -Uri 'https://graph.microsoft.com/v1.0/security/secureScoreControlProfiles' -AccessToken $graphToken
        $profileMap = [ordered]@{
            control_name        = 'controlName'
            control_category    = 'controlCategory'
            title               = 'title'
            max_score           = 'maxScore'
            rank                = 'rank'
            service             = 'service'
            action_type         = 'actionType'
            user_impact         = 'userImpact'
            implementation_cost = 'implementationCost'
            tier                = 'tier'
            threats             = { param($p) $p.threats | Join-ImperionValues }
            remediation         = 'remediation'
            deprecated          = 'deprecated'
        }
        $profileRows = $profiles | ConvertTo-ImperionFlatObject -PropertyMap $profileMap -Source 'securescore' -TenantId $TenantId -ExternalIdProperty 'id'
        $t2 = if ($profileRows) { Invoke-ImperionBronzeUpsert -Connection $conn -Table 'secure_score_control_profiles' -Rows $profileRows } else { [pscustomobject]@{ scanned = 0; inserted = 0; updated = 0; unchanged = 0 } }
        Write-ImperionLog -Level Metric -Source 'securescore' -Message 'secure_score_control_profiles synced.' -Data @{ scanned = $t2.scanned; inserted = $t2.inserted; updated = $t2.updated; unchanged = $t2.unchanged }
    }
    finally { $conn.Dispose() }

    Write-ImperionLog -Level Metric -Source 'securescore' -Message 'Secure Score sync complete.' -Data @{ tenant = $TenantId; seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 1) }
}
