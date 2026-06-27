function Invoke-ImperionServicePrincipalSync {
    <#
    .SYNOPSIS
        Inventory Entra service principals, optionally document them in IT Glue, and land them in Postgres bronze.
    .DESCRIPTION
        Canonical flatten -> IT Glue -> Postgres pattern (ADR-0006). Per-client security posture
        (ADR-0126): fans out over EVERY mapped client tenant via Invoke-ImperionM365EstateSweep —
        the same registry-driven (account_tenant join an active m365 connection), per-tenant
        fail-isolated sweep the directory collectors already use (#358/#266) — instead of the home
        tenant only. A tenant with no consent/credential is skipped (Warn) and never blocks the
        rest. Idempotent (change-detected upsert) — re-runs converge. Requires
        Initialize-ImperionContext.
    .PARAMETER TenantId
        Pins the sweep to one tenant (the tenant-outer driver, #359); omit for the registry-driven
        estate fan-out (#358). Customer tenants are reached via the per-client onboarding app (§3).
    .PARAMETER OrganizationId
        IT Glue organization id to relate assets to. Omit (or -SkipITGlue) to skip the hub write.
    .PARAMETER SkipITGlue
        Postgres only — skip the IT Glue documentation write.
    .PARAMETER CreateTypeIfMissing
        Create the 'Azure Service Principal' flexible asset type if absent (one-time setup).
    .EXAMPLE
        Invoke-ImperionServicePrincipalSync -OrganizationId 42
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string] $TenantId,
        [int] $OrganizationId,
        [switch] $SkipITGlue,
        [switch] $CreateTypeIfMissing
    )

    # Fan out over the mapped client tenants (ADR-0126); -TenantId pins one (#359). The original
    # single-tenant body runs verbatim per tenant inside the fail-isolated sweep (#358/#266); a
    # $null tenant (empty registry, dormant-safe) falls back to the partner tenant as before.
    $sweep = @{}
    if ($PSBoundParameters.ContainsKey('TenantId')) { $sweep.TenantId = $TenantId }
    Invoke-ImperionM365EstateSweep @sweep -Source 'm365' -Label 'Entra service principals' -PerTenant {
        param($TenantId)
        Invoke-ImperionServicePrincipalSyncForTenant -TenantId $TenantId `
            -OrganizationId $OrganizationId -SkipITGlue:$SkipITGlue -CreateTypeIfMissing:$CreateTypeIfMissing
    }
}

function Invoke-ImperionServicePrincipalSyncForTenant {
    <#
    .SYNOPSIS
        Inventory one tenant's Entra service principals → (optional IT Glue) → Postgres bronze.
    .DESCRIPTION
        The single-tenant body behind Invoke-ImperionServicePrincipalSync — split out so the public
        cmdlet can fan it out per mapped client tenant via Invoke-ImperionM365EstateSweep (ADR-0126).
        Identical flatten -> IT Glue -> Postgres pattern (ADR-0006); a $null -TenantId falls back to
        the partner tenant (dormant-safe). Requires Initialize-ImperionContext.
    .PARAMETER TenantId
        Tenant to inventory; $null/empty falls back to the partner tenant.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string] $TenantId,
        [int] $OrganizationId,
        [switch] $SkipITGlue,
        [switch] $CreateTypeIfMissing
    )

    $cfg = Get-ImperionConfig
    $names = Get-ImperionSecretNames
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }
    $source = 'm365'
    $started = Get-Date

    $graphToken = Get-ImperionGraphToken -TenantId $TenantId
    $servicePrincipals = Invoke-ImperionGraphRequest -Uri 'https://graph.microsoft.com/v1.0/servicePrincipals' -AccessToken $graphToken
    Write-ImperionLog -Source $source -Message "Fetched $($servicePrincipals.Count) service principals from tenant $TenantId."

    $nearestExpiry = {
        param($expiryCandidates)
        if (-not $expiryCandidates) { return $null }
        ($expiryCandidates | Where-Object { $_.endDateTime } | Sort-Object endDateTime | Select-Object -First 1).endDateTime
    }
    $propertyMap = [ordered]@{
        app_id                     = 'appId'
        display_name               = 'displayName'
        sp_type                    = 'servicePrincipalType'
        account_enabled            = 'accountEnabled'
        app_owner_org_id           = 'appOwnerOrganizationId'
        sign_in_audience           = 'signInAudience'
        homepage                   = 'homepage'
        reply_urls                 = { param($sp) (Get-ImperionMember $sp 'replyUrls') | Join-ImperionValues }
        sp_names                   = { param($sp) (Get-ImperionMember $sp 'servicePrincipalNames') | Join-ImperionValues }
        tags                       = { param($sp) (Get-ImperionMember $sp 'tags') | Join-ImperionValues }
        app_roles_count            = { param($sp) (Get-ImperionMember $sp 'appRoles' | Measure-Object).Count }
        oauth2_scopes_count        = { param($sp) (Get-ImperionMember $sp 'oauth2PermissionScopes' | Measure-Object).Count }
        key_credentials_count      = { param($sp) (Get-ImperionMember $sp 'keyCredentials' | Measure-Object).Count }
        key_credential_next_expiry = { param($sp) & $nearestExpiry (Get-ImperionMember $sp 'keyCredentials') }
        pwd_credentials_count      = { param($sp) (Get-ImperionMember $sp 'passwordCredentials' | Measure-Object).Count }
        pwd_credential_next_expiry = { param($sp) & $nearestExpiry (Get-ImperionMember $sp 'passwordCredentials') }
        created_date_time          = 'createdDateTime'
    }
    $flat = $servicePrincipals | ConvertTo-ImperionFlatObject -PropertyMap $propertyMap -Source $source -TenantId $TenantId -ExternalIdProperty 'id'

    if (-not $SkipITGlue -and $OrganizationId) {
        $writeKey = Get-ImperionSecretValue -Name $names.ITGlueWriteKey
        $documented = 0
        foreach ($row in $flat) {
            $traits = @{
                'display-name'     = $row.display_name
                'app-id'           = $row.app_id
                'sp-type'          = $row.sp_type
                'account-enabled'  = $row.account_enabled
                'sign-in-audience' = $row.sign_in_audience
                'sp-names'         = $row.sp_names
                'key-cred-expiry'  = $row.key_credential_next_expiry
                'pwd-cred-expiry'  = $row.pwd_credential_next_expiry
            }
            if ($PSCmdlet.ShouldProcess("IT Glue org $OrganizationId / app-id $($row.app_id)", 'Document service principal')) {
                Set-ImperionITGlueFlexibleAsset -ApiKey $writeKey -TypeName 'Azure Service Principal' `
                    -OrganizationId $OrganizationId -MatchTrait 'app-id' -MatchValue $row.app_id `
                    -Traits $traits -CreateTypeIfMissing:$CreateTypeIfMissing | Out-Null
                $documented++
            }
        }
        Write-ImperionLog -Source $source -Message "Documented $documented service principals to IT Glue org $OrganizationId."
    }
    elseif (-not $SkipITGlue) {
        Write-ImperionLog -Level Warn -Source $source -Message 'No -OrganizationId provided; skipping IT Glue documentation.'
    }

    if (-not $PSCmdlet.ShouldProcess('Postgres bronze m365_service_principals', "Upsert $($flat.Count) service-principal rows")) {
        return
    }
    $conn = New-ImperionDbConnection
    try {
        $tally = Invoke-ImperionBronzeUpsert -Connection $conn -Table 'm365_service_principals' -Rows $flat
    }
    finally { $conn.Dispose() }

    Write-ImperionLog -Level Metric -Source $source -Message 'Service-principal sync complete.' -Data @{
        tenant = $TenantId; scanned = $tally.scanned; inserted = $tally.inserted; updated = $tally.updated; unchanged = $tally.unchanged
        seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
    }
}
