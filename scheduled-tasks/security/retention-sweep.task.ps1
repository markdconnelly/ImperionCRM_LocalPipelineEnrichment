# security/retention-sweep - daily 180-day prune of the security-incident bronze rows
# (m365_incidents / m365_alerts / m365_evidence ONLY, issue #196 / ADR-0019 §3).
# Cadence: Daily (scheduled-tasks/README.md) - a daily sweep keeps the window tight; idempotent.
#
# SCOPE: exactly the three m365_* security tables, leaf-first (evidence -> alerts -> incidents).
# Does NOT touch interaction bronze, does NOT touch purview_compliance_*, NOT system-wide.
# WHY 180 DAYS IS SAFE: Autotask is the durable system of record for incident history (ADR-0019 §1);
# the DB keeps only a recent operational window. Bounding it also shrinks the standing PII surface
# (evidence can carry hostnames / user ids / IPs) - the retention bound is itself a security control.
#
# This DELETES data. The cmdlet is -WhatIf/-Confirm aware and logs COUNT-ONLY (never row content).
# DORMANT until creds provisioned (#102) - and like every write path the first live run is gated:
# surface before enabling (CLAUDE.md §8). Run a -WhatIf dry run first to confirm the eligible counts.
#
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion-Security-RetentionSweep' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\security\retention-sweep.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

try {
    # -Confirm:$false: the scheduled run is unattended; the gate is the deliberate enablement of this
    # task (CLAUDE.md §8), not an interactive prompt. Default 180 days (ADR-0019 §3).
    Invoke-ImperionSecurityRetentionSweep -Confirm:$false
}
catch {
    # A missing table or transient DB error must not crash the schedule - log loudly and exit;
    # the next run converges (idempotent: already-pruned rows are simply absent).
    Write-ImperionLog -Level Warn -Source 'm365' -Message "Security retention sweep skipped: $($_.Exception.Message)"
}
