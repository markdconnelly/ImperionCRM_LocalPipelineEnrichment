# azure/cloud-asset-merge - fold the Azure ARM cloud-resource bronze into the
# provider-agnostic silver cloud_asset the CMDB cloud CI arm reads (ADR-0026
# merge-co-locates-with-ingestion, migration 2). The on-prem twin of the cloud Pipeline's
# mergeCloudAssetSources (ImperionCRM_Pipeline src/shared/merge-cloud-asset.ts, front-end
# #874 / migration 0139); the cloud copy is ceded once this is live (Pipeline #135).
#
# Runs AFTER the collector (azure/cloud-resources.task.ps1, ADR-0023) so it folds the
# freshest bronze. Cadence: Daily - cloud inventory changes slowly and the upsert is
# idempotent (ON CONFLICT on (provider, external_id)), so re-runs are cheap and converge.
# Compose one cmdlet; keep this file short (CLAUDE.md section 1).
#
# GATED: until front-end migration 0139 (silver cloud_asset) is applied to prod AND the
# collector has written cloud_resources bronze, the merge is a clean no-op or the table is
# absent; the catch below logs a Warn and exits cleanly so the schedule never crashes. The
# CMDB cloud view stays empty until account_tenant maps a tenant to an account (Settings →
# Tenant mapping) - unmapped rows are kept with NULL account_id and filtered by the view.
#
# Registration: this is registered by Register-ImperionTask as the task
# '\Imperion\Imperion-CloudAssetMerge' (the cmdlet runs directly; the $tasks array is the
# single source of truth — Register-ImperionTask takes -TaskCredential/-TaskIdentity, NOT
# per-task -Name/-Command). Run elevated, under the gMSA/service identity:
#
#   Register-ImperionTask -TaskCredential (Get-Credential '.\svc-imperion')   # registers all tasks
#   Start-ScheduledTask -TaskName 'Imperion-CloudAssetMerge' -TaskPath '\Imperion\'   # run once now
#
# This file remains a standalone/manual entry point (adds the schema-gate try/catch below).

Import-Module ImperionPipeline
Initialize-ImperionContext

try {
    Invoke-ImperionCloudAssetMerge | Out-Null
}
catch {
    # Schema gate / transient: log loudly and exit; the next run converges (idempotent upsert).
    Write-ImperionLog -Level Warn -Source 'azure' -Message "Cloud asset merge skipped: $($_.Exception.Message)"
}
