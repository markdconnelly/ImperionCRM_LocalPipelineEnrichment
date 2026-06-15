# m365/sensitivity-labels - daily information-protection taxonomy pull -> bronze
# (sensitivity_labels, issue #141 / front-end schema issue ImperionCRM#259).
# Cadence: Daily (scheduled-tasks/README.md) - label taxonomy is slow-changing; the
# change-detected upsert keeps re-runs cheap. Composes one get + one post; keep this short
# (CLAUDE.md §1). Auth is the module's cert-SP Graph token (SensitivityLabels.Read.All,
# read-only, part of the read-only-by-default grant); single-tenant against the Imperion
# company tenant by default - set IMPERION_M365_TENANT_IDS for GDAP fan-out (per-tenant
# isolation: each row is stamped with its owning tenant). Benchmark-vs-golden classification
# runs in the front-end posture merge (#259), not here.
#
# GATED: until the front-end sensitivity_labels migration (#259) is applied to prod the post
# fails loudly; the catch below logs a Warn and exits cleanly so the schedule never crashes.
#
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion m365 sensitivity-labels' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\m365\sensitivity-labels.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

try {
    $tenantIds = @($env:IMPERION_M365_TENANT_IDS -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($tenantIds.Count -eq 0) {
        Get-ImperionSensitivityLabel | Set-ImperionSensitivityLabelToBronze
    }
    else {
        foreach ($tenantId in $tenantIds) {
            Get-ImperionSensitivityLabel -TenantId $tenantId | Set-ImperionSensitivityLabelToBronze
        }
    }
}
catch {
    # Schema/permission gate: log loudly and exit; the operator lands the #259 prod apply
    # and the next run converges (idempotent, change-detected upsert).
    Write-ImperionLog -Level Warn -Source 'm365' -Message "Sensitivity labels sync skipped: $($_.Exception.Message)"
}
