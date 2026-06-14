# autotask/time-entries - scheduled Autotask TimeEntry bulk pull -> autotask_time_entry bronze.
# Cadence: Hourly (scheduled-tasks/README.md) — authoritative bulk reconcile for employee time
# tracking (ADR-0082); the cloud Pipeline PL-2 (ImperionCRM_Pipeline#101) handles on-demand
# "refresh now". Composes one get + one post; keep this short (CLAUDE.md §1). The functions do
# the heavy lifting so they stay reusable by full backfills.
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion autotask time-entries' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\autotask\time-entries.task.ps1"' `
#     -Interval Hourly

Import-Module ImperionPipeline
Initialize-ImperionContext

# Incremental on lastModifiedDateTime; set IMPERION_AUTOTASK_TIME_SINCE_DAYS=0 for a full
# authoritative backfill (the local pipeline owns the historical window).
$sinceDays = if ($env:IMPERION_AUTOTASK_TIME_SINCE_DAYS) { [int]$env:IMPERION_AUTOTASK_TIME_SINCE_DAYS } else { 7 }

Get-ImperionAutotaskTimeEntry -SinceDays $sinceDays | Set-ImperionAutotaskTimeEntryToBronze
