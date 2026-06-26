function Invoke-ImperionTenantHydration {
    <#
    .SYNOPSIS
        Hydrate the Microsoft 365 estate tenant-by-tenant — acquire each consented tenant's Graph
        token once, then run the full estate-collector set for that tenant before cycling to the next.
    .DESCRIPTION
        The tenant-outer driver for the 365 estate (epic #324 slice 3b, ADR-0030 Decision #4). It
        reverses the per-collector fan-out: instead of one scheduled task per source each sweeping
        every tenant (routines-outer), this runs ONE job that, per consented tenant, acquires the
        tenant's Graph token once and runs every estate collector pinned to that tenant
        (tenant-outer, routines-inner). Two wins over the per-collector model:

          - **One token per tenant, reused across its routines.** The up-front `Get-ImperionGraphToken`
            populates the per-`(tenant,resource)` cache in `Get-ImperionAccessToken`, so each routine
            below reuses it instead of re-minting — lower Graph token churn (it all runs in one
            process, unlike the separate per-collector tasks).
          - **A client's full picture lands together** in one run, with per-tenant success/skip
            visibility in a single Metric line.

        Tenants come from the consented-tenant registry (`Get-ImperionConsentedTenant`:
        `account_tenant ⨝` an active `m365` `connection`) — GUI-save is the enable (#358), no host
        env edit. A tenant whose token cannot be acquired (no consent / credential) **fails closed**
        and is skipped whole (Warn), never touched (CLAUDE.md §3); the up-front acquire means an
        unconsented tenant is skipped once rather than failing all N routines. Per-routine failures
        are isolated too (each routine already isolates per tenant inside the sweep; the inner guard
        here keeps one routine's unexpected failure from aborting the rest for that tenant). Idempotent
        end to end (the collectors are change-detected upserts) — a re-run converges. Requires
        Initialize-ImperionContext.

        Scope: this driver owns the per-tenant **Graph estate sweep** only — the 14 sweep-based
        collectors. The set-based bronze→silver MERGES (`Invoke-ImperionM365DirectoryMerge`,
        `Invoke-ImperionPostureMerge`) run once across all tenants and keep their own scheduled
        entries; the non-sweep collectors (Secure Score, service principals, security incidents,
        Azure cloud-resources, mail/Teams) likewise keep theirs.
    .PARAMETER TenantId
        Explicit tenant id list; defaults to the consented-tenant registry. Mainly for tests / a
        deliberate targeted run.
    .PARAMETER Routine
        Explicit ordered list of estate-collector cmdlet names; defaults to the 14 sweep-based
        m365 collectors. Each is invoked as `& $routine -TenantId <tenant>`. Mainly for tests.
    .EXAMPLE
        Invoke-ImperionTenantHydration
    .EXAMPLE
        Invoke-ImperionTenantHydration -TenantId '49307c12-1bb7-42e4-9c7c-43d2850bd8c6'
    #>
    [CmdletBinding()]
    param(
        [string[]] $TenantId,
        [string[]] $Routine
    )

    $started = Get-Date

    if (-not $Routine) {
        $Routine = @(
            'Invoke-ImperionM365UserSync'
            'Invoke-ImperionM365DeviceSync'
            'Invoke-ImperionEntraGroupSync'
            'Invoke-ImperionEntraGroupMemberSync'
            'Invoke-ImperionEntraDomainSync'
            'Invoke-ImperionEntraAppRegistrationSync'
            'Invoke-ImperionEntraRoleAssignmentSync'
            'Invoke-ImperionEntraAuthMethodSync'
            'Invoke-ImperionIntuneAppSync'
            'Invoke-ImperionIntuneDeviceSync'
            'Invoke-ImperionSensitivityLabelSync'
            'Invoke-ImperionCustomSecurityAttributeSync'
            'Invoke-ImperionSharePointSiteSync'
            'Invoke-ImperionDefenderSync'
        )
    }

    if (-not $TenantId) { $TenantId = @(Get-ImperionConsentedTenant) }
    $tenants = @($TenantId | Where-Object { $_ })
    if ($tenants.Count -eq 0) {
        Write-ImperionLog -Level Warn -Source 'm365' -Message 'Tenant hydration: no consented tenants in the registry — nothing to hydrate.'
        return
    }

    $hydratedTenants = 0
    $skippedTenants = 0
    $routineFailures = 0
    foreach ($tenant in $tenants) {
        try {
            # Acquire the tenant's Graph token ONCE up front (ADR-0030 Decision #4) — this both
            # fails closed for an unconsented/uncredentialed tenant (skip the whole tenant rather
            # than fail every routine) and warms the per-(tenant,resource) token cache the routines
            # below reuse.
            $null = Get-ImperionGraphToken -TenantId $tenant
        }
        catch {
            $skippedTenants++
            Write-ImperionLog -Level Warn -Source 'm365' -Message "Tenant hydration skipped for tenant '$tenant' (no consent/credential): $($_.Exception.Message)"
            continue
        }

        # NB: the loop variable must NOT be $routine — PowerShell variable names are
        # case-insensitive, so $routine and the $Routine parameter are the SAME variable; using
        # $routine here clobbers $Routine to a scalar after the first tenant, so every later tenant
        # would run only its last routine. $routineName keeps them distinct.
        foreach ($routineName in $Routine) {
            try {
                & $routineName -TenantId $tenant
            }
            catch {
                $routineFailures++
                Write-ImperionLog -Level Warn -Source 'm365' -Message "Tenant hydration: routine '$routineName' failed for tenant '$tenant': $($_.Exception.Message)"
            }
        }
        $hydratedTenants++
    }

    Write-ImperionLog -Level Metric -Source 'm365' -Message 'Tenant hydration complete.' -Data @{
        tenants_registered  = $tenants.Count
        tenants_hydrated    = $hydratedTenants
        tenants_skipped     = $skippedTenants
        routines_per_tenant = $Routine.Count
        routine_failures    = $routineFailures
        duration_s          = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
    }
}
