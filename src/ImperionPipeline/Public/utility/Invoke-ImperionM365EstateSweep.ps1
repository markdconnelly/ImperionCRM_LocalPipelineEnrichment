function Invoke-ImperionM365EstateSweep {
    <#
    .SYNOPSIS
        Fan an M365 collector out across the tenant estate with absolute per-tenant
        fail-isolation (issue #266).
    .DESCRIPTION
        The shared estate-sweep helper for the m365 `*.task.ps1` collectors. Every m365 task
        pulls one source across the consented-tenant estate. The tenant list defaults to the
        credential registry (`Get-ImperionConsentedTenant`: `account_tenant` joined to an active
        `m365` `connection`) so a credential saved in the GUI hydrates on the next run with no
        host env edit (ADR-0030 'GUI-as-enable'). `IMPERION_M365_TENANT_IDS`, when set, overrides
        the registry as an operator pin (back-compat); an empty registry AND unset env means the
        partner tenant only (dormant-safe).

        Before this helper each task ran its own `foreach`, and its try/catch — when it had
        one at all — sat OUTSIDE the loop. So a single unconsented or misconfigured tenant
        (`Get-ImperionGraphToken` now fails closed, #250 / ADR-0028 §3) aborted the whole task
        and every later tenant. This centralizes the fan-out and makes per-tenant isolation
        absolute: each tenant runs inside its own try/catch (the LP #234
        `Invoke-ImperionCloudResourceSync` precedent) — a tenant that throws (no
        consent/credential, or the source's bronze table not yet applied) is logged Warn and
        SKIPPED, never blocking the rest. One Metric line summarizes registered/swept/skipped.

        The collector + bronze writer for one tenant are supplied as -PerTenant; it receives
        the tenant id ($null for the partner tenant) so the task composes the source's own
        get|set pipeline. Idempotent end to end (change-detected upsert) — re-runs converge.
        Requires Initialize-ImperionContext.
    .PARAMETER PerTenant
        Script block invoked once per tenant with the tenant id as its only argument
        ($null = partner tenant, i.e. call the collector with no -TenantId).
    .PARAMETER Source
        Log source key for the run (default 'm365'; the Defender task passes 'defender').
    .PARAMETER Label
        Human-readable label for the Warn/Metric messages (e.g. 'Entra auth-methods').
    .PARAMETER TenantId
        Explicit tenant list; defaults to IMPERION_M365_TENANT_IDS. Mainly for tests.
    .EXAMPLE
        Invoke-ImperionM365EstateSweep -Label 'M365 users' -PerTenant {
            param($TenantId)
            if ($TenantId) { Get-ImperionM365User -TenantId $TenantId | Set-ImperionM365UserToBronze }
            else { Get-ImperionM365User | Set-ImperionM365UserToBronze }
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock] $PerTenant,
        [string] $Source = 'm365',
        [string] $Label = 'M365 estate',
        [string[]] $TenantId
    )

    $started = Get-Date

    # Resolve the fan-out list with this precedence (ADR-0030 Decision #4 — registry-as-enable):
    #   1. an explicit -TenantId (tests / a deliberate single-tenant run);
    #   2. IMPERION_M365_TENANT_IDS, when set — an operator PIN / override (back-compat: a host
    #      that still sets it keeps working, and it can pin a subset for a targeted run);
    #   3. otherwise the consented-tenant registry (account_tenant join an active m365 connection)
    #      — the DEFAULT, so a credential saved in the GUI hydrates on the next run with NO host
    #      env edit (CLAUDE.md §1 pull/registry-driven; ADR-0030 'GUI-as-enable');
    #   4. an empty registry => the partner tenant only, a single $null iteration so the
    #      collector runs with no -TenantId (dormant-safe).
    if (-not $PSBoundParameters.ContainsKey('TenantId')) {
        $envTenants = @($env:IMPERION_M365_TENANT_IDS -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        if ($envTenants.Count -gt 0) {
            $TenantId = $envTenants
        }
        else {
            $TenantId = @(Get-ImperionConsentedTenant)
        }
    }
    $tenantIds = @($TenantId | Where-Object { $_ })
    if ($tenantIds.Count -eq 0) {
        $tenantIds = @($null)
    }

    $sweptTenants = 0
    $skippedTenants = 0
    foreach ($tenant in $tenantIds) {
        try {
            & $PerTenant $tenant
            $sweptTenants++
        }
        catch {
            # Consent/credential gap or the source's bronze not yet applied: log loudly and
            # continue to the next tenant. The next run converges once access/schema exist.
            $skippedTenants++
            $scope = if ($tenant) { "tenant '$tenant'" } else { 'the partner tenant' }
            Write-ImperionLog -Level Warn -Source $Source -Message "$Label sync skipped for ${scope}: $($_.Exception.Message)"
        }
    }

    Write-ImperionLog -Level Metric -Source $Source -Message "$Label estate swept." -Data @{
        tenants_registered = $tenantIds.Count
        tenants_swept      = $sweptTenants
        tenants_skipped    = $skippedTenants
        duration_s         = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
    }
}
