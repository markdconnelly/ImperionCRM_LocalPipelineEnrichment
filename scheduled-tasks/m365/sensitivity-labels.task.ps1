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
# fails loudly; the estate-sweep helper logs a Warn per tenant and continues so the schedule
# never crashes.
#
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion m365 sensitivity-labels' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\m365\sensitivity-labels.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

Invoke-ImperionM365EstateSweep -Label 'Sensitivity labels' -PerTenant {
    param($TenantId)
    if ($TenantId) { Get-ImperionSensitivityLabel -TenantId $TenantId | Set-ImperionSensitivityLabelToBronze }
    else { Get-ImperionSensitivityLabel | Set-ImperionSensitivityLabelToBronze }
}
