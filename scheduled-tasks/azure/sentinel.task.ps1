# azure/sentinel - daily Microsoft Sentinel object pull -> bronze (sentinel_* tables).
# Cadence: Daily (scheduled-tasks/README.md). Composes one get + one post; keep this short
# (CLAUDE.md §1). Auth is the cert SP's existing Azure RBAC Reader (no new grant, issue #97);
# workspaces without Sentinel are logged + skipped inside the get.
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion azure sentinel' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\azure\sentinel.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

Get-ImperionSentinelObject | Set-ImperionSentinelToBronze
