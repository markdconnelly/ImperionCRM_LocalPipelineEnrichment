# docusign/envelopes - daily DocuSign envelope pull -> bronze (docusign_contracts).
# Cadence: Daily (scheduled-tasks/README.md). Composes one get + one post; keep this short
# (CLAUDE.md §1). Credentials are SecretStore secrets (docusign-token / docusign-account-id,
# CLAUDE.md §2). GATED: until the operator provisions both secrets, the task logs the gap
# and exits cleanly (never crashes the schedule) - see docs/integrations/docusign.md.
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion docusign envelopes' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\docusign\envelopes.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

# Incremental window; set IMPERION_DOCUSIGN_SINCE_DAYS=0 for a full backfill from 2000-01-01.
$sinceDays = if ($env:IMPERION_DOCUSIGN_SINCE_DAYS) { [int]$env:IMPERION_DOCUSIGN_SINCE_DAYS } else { 7 }
$fromDate = if ($sinceDays -le 0) { '2000-01-01' } else { (Get-Date).AddDays(-$sinceDays).ToString('yyyy-MM-dd') }

try {
    Get-ImperionDocuSignEnvelope -FromDate $fromDate | Set-ImperionDocuSignContractToBronze
}
catch {
    # Credential gate: missing/expired docusign-token or docusign-account-id must not
    # crash the schedule - log loudly and exit; the operator re-provisions and the next
    # run converges (idempotent upsert).
    Write-ImperionLog -Level Warn -Source 'docusign' -Message "DocuSign envelope sync skipped: $($_.Exception.Message)"
}
