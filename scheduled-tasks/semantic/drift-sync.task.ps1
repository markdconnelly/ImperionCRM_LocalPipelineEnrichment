# semantic/drift-sync - OKF semantic-layer drift agent (issue #175 / ADR-0086).
#
# Detects drift between the live silver schema (column names only - no data, no PII) and the
# front-end OKF semantic-layer bundle (markdconnelly/ImperionCRM, docs/database/semantic-layer/),
# and proposes a sync. This repo does the bronze->silver->gold shaping and ALL vectorization, so
# it "knows" the silver shape - the right home for staleness ownership (ADR-0086 constraint 3,
# system CLAUDE.md section 11). The agent PROPOSES; humans approve. It NEVER forks concept files
# into this repo and NEVER edits the bundle directly - the front end owns the canon.
#
# Cadence: Weekly (slow-moving doc surface; runs after the merge tasks so it sees the freshest
# silver shape). The detection read is idempotent and side-effect-free.
#
# DORMANT / fail-closed by default:
#   - No -Execute  -> DRY RUN: detect + log drift, open nothing. This is the default the schedule
#     registers, so a cold node simply logs what drifted.
#   - -Execute     -> opens a cross-repo PR on the front-end repo with the drifted concept files
#     already edited on a branch (issue #190; falls back to an issue for author-only drift). The
#     agent NEVER merges. Fail-closed: needs a GitHub token in $env:IMPERION_GH_TOKEN or it logs a
#     Warn and exits (never prompts, never stores/prints the token). Enable only once Mark provisions
#     a least-privileged, branch-write-only token.
#   - No bundle / no DB access -> clean no-op (logged), never crashes the schedule.
#
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion semantic drift-sync' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\semantic\drift-sync.task.ps1"' `
#     -Interval Weekly

Import-Module ImperionPipeline
Initialize-ImperionContext

# Flip to -Execute (and provision $env:IMPERION_GH_TOKEN) once cross-repo proposals are approved
# to open automatically. Until then: detect-and-log only.
$execute = [bool]$env:IMPERION_SEMANTIC_DRIFT_EXECUTE

try {
    Invoke-ImperionSemanticDriftSync -Execute:$execute | Out-Null
}
catch {
    # Schema gate / transient / no access: log loudly and exit; the next run converges.
    Write-ImperionLog -Level Warn -Source 'semantic' -Message "Semantic drift-sync skipped: $($_.Exception.Message)"
}
