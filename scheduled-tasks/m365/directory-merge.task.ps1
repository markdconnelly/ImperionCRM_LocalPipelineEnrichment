# m365/directory-merge - fold Entra group membership into the silver contact_enrichment
# dossier (directory_groups fact). The on-prem bronze→silver merge for M365 directory
# groups (ADR-0026, merge-co-locates-with-ingestion; generalizes the posture-merge
# precedent ADR-0010). Ported from the cloud Pipeline's mergeDirectoryGroups
# (ImperionCRM_Pipeline src/shared/merge-directory.ts, #93 / front-end migration 0079);
# the cloud copy is ceded once this is live (Pipeline #134).
#
# Runs AFTER the directory collectors so it folds the freshest bronze:
#   m365/entra-groups (m365_groups), m365/entra-group-members (m365_group_members),
#   m365/users (m365_contacts). Cadence: Daily - directory membership changes slowly and
#   the merge is idempotent (full replace of the m365_directory source), so re-runs are
#   cheap and converge. Compose one cmdlet; keep this file short (CLAUDE.md section 1).
#
# GATED: until front-end migration 0079 (m365_groups / m365_group_members) is applied to
# prod AND the collectors have run, the merge has no candidates (clean no-op) or the
# tables are absent; the catch logs a Warn and exits cleanly so the schedule never crashes.
#
# Registration: this is registered by Register-ImperionTask as the task
# '\Imperion\Imperion-M365DirectoryMerge' (the cmdlet runs directly; the $tasks array is the
# single source of truth — Register-ImperionTask takes -TaskCredential/-TaskIdentity, NOT
# per-task -Name/-Command). Run elevated, under the gMSA/service identity:
#
#   Register-ImperionTask -TaskCredential (Get-Credential '.\svc-imperion')   # registers all tasks
#   Start-ScheduledTask -TaskName 'Imperion-M365DirectoryMerge' -TaskPath '\Imperion\'   # run once now
#
# This file remains a standalone/manual entry point (adds the schema-gate try/catch below).

Import-Module ImperionPipeline
Initialize-ImperionContext

try {
    Invoke-ImperionM365DirectoryMerge | Out-Null
}
catch {
    # Schema gate / transient: log loudly and exit; the next run converges (idempotent replace).
    Write-ImperionLog -Level Warn -Source 'm365' -Message "M365 directory merge skipped: $($_.Exception.Message)"
}
