function Invoke-ImperionMergeByPlan {
    <#
    .SYNOPSIS
        Run a declarative bronze->silver Merge Plan: the shared orchestration scaffold
        behind the Invoke-Imperion*Merge cmdlets (epic #429, ADR-0026).
    .DESCRIPTION
        Extracts the orchestration that every LP-ingested merge repeats so each merge
        cmdlet collapses to a thin Plan-builder. The scaffold owns the *how* — connection
        lifecycle, ShouldProcess, transaction discipline, @t injection, tally, and
        structured logging — while the Plan supplies the *what* (declarative SQL steps).
        Behaviour is byte-identical to the hand-rolled cmdlets it replaces.

        Two scopes:
          - Scope='Global'    : run the steps in order, per-statement autocommit, NO
                                wrapping transaction (the set-based, single-pass merges).
          - Scope='PerTenant' : enumerate tenants (TenantEnumerationSql, or -TenantId),
                                and run ALL steps for one tenant inside ONE transaction,
                                injecting @t into every step. A failing tenant rolls back
                                its own transaction, is logged, and never blocks the
                                fleet; the run is idempotent so a re-run converges.

        Steps are fully declarative: @{ Name; Sql; Parameters? } — no scriptblocks. The
        original step Parameters are never mutated (a clone carries @t), so the same Plan
        re-runs identically across tenants and across runs.
    .PARAMETER Plan
        Hashtable describing the merge:
          Source               log source label (string)
          Scope                'Global' | 'PerTenant'
          TenantEnumerationSql (PerTenant) SQL returning a tenant_id column
          Steps                array of @{ Name; Sql; Parameters? }
    .PARAMETER TenantId
        (PerTenant) optional tenant subset; overrides TenantEnumerationSql.
    .PARAMETER Connection
        Optional open Npgsql connection to reuse; otherwise one is opened and disposed.
    .EXAMPLE
        Invoke-ImperionMergeByPlan -Plan @{
            Source = 'dns'; Scope = 'Global'
            Steps  = @(@{ Name = 'upsert_dns'; Sql = $upsertSql })
        }
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][hashtable] $Plan,
        [string[]] $TenantId,
        $Connection
    )

    $started = Get-Date
    $ownConnection = -not $Connection
    if ($ownConnection) { $Connection = New-ImperionDbConnection }

    # tally: rows affected, summed per step Name, in declared order.
    $tally = [ordered]@{}
    foreach ($step in $Plan.Steps) { $tally[$step.Name] = 0 }

    try {
        if ($Plan.Scope -eq 'PerTenant') {
            # Resolve the tenant set: explicit -TenantId wins, else enumerate.
            if (-not $TenantId) {
                $TenantId = @(Invoke-ImperionDbQuery -Connection $Connection -Sql $Plan.TenantEnumerationSql |
                        Select-Object -ExpandProperty tenant_id)
            }

            $tenantsMerged = 0
            $tenantsFailed = 0

            foreach ($tenant in @($TenantId)) {
                if (-not $PSCmdlet.ShouldProcess($tenant, "Merge $($Plan.Source) silver")) { continue }

                $transaction = $Connection.BeginTransaction()
                try {
                    # Accumulate this tenant's rows in a subtotal; fold into the run tally
                    # only on commit, so a rolled-back tenant never inflates it (accuracy).
                    $tenantTally = @{}
                    foreach ($step in $Plan.Steps) {
                        # Inject @t into a CLONE of the step's params so the original Plan
                        # is never mutated (re-run / next-tenant convergence).
                        $params = if ($step.ContainsKey('Parameters') -and $step.Parameters) { $step.Parameters.Clone() } else { @{} }
                        $params['t'] = $tenant
                        $tenantTally[$step.Name] = (Invoke-ImperionDbNonQuery -Connection $Connection -Sql $step.Sql -Parameters $params)
                    }
                    $transaction.Commit()
                    foreach ($name in $tenantTally.Keys) { $tally[$name] += $tenantTally[$name] }
                    $tenantsMerged++
                }
                catch {
                    # One bad tenant never blocks the fleet: roll back, log, continue.
                    $transaction.Rollback()
                    $tenantsFailed++
                    Write-ImperionLog -Level Error -Source $Plan.Source `
                        -Message "Merge failed for tenant $tenant - rolled back." `
                        -Data @{ tenant = $tenant; error = $_.Exception.Message }
                }
                finally { $transaction.Dispose() }
            }

            Write-ImperionLog -Level Metric -Source $Plan.Source -Message "Merge plan complete ($($Plan.Source))." -Data @{
                scope   = $Plan.Scope
                tenants = @($TenantId).Count
                merged  = $tenantsMerged
                failed  = $tenantsFailed
                tally   = $tally
                seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
            }

            return [pscustomobject]@{
                source        = $Plan.Source
                scope         = $Plan.Scope
                tally         = $tally
                tenantsMerged = $tenantsMerged
                tenantsFailed = $tenantsFailed
            }
        }

        # Global: no wrapping transaction, run each step once.
        foreach ($step in $Plan.Steps) {
            if (-not $PSCmdlet.ShouldProcess($Plan.Source, "Merge step '$($step.Name)'")) { continue }
            $params = if ($step.ContainsKey('Parameters') -and $step.Parameters) { $step.Parameters } else { @{} }
            $tally[$step.Name] += Invoke-ImperionDbNonQuery -Connection $Connection -Sql $step.Sql -Parameters $params
        }

        Write-ImperionLog -Level Metric -Source $Plan.Source -Message "Merge plan complete ($($Plan.Source))." -Data @{
            scope   = $Plan.Scope
            tally   = $tally
            seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
        }

        return [pscustomobject]@{
            source = $Plan.Source
            scope  = $Plan.Scope
            tally  = $tally
        }
    }
    finally { if ($ownConnection) { $Connection.Dispose() } }
}
