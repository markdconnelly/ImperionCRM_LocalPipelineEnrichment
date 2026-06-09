# autotask/contracts - daily Autotask contract reconcile -> bronze.
# Cadence: Daily (scheduled-tasks/README.md). Composes one get + one post; keep this short
# (CLAUDE.md §1). The functions do the heavy lifting so they stay reusable by backfills.
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion autotask contracts' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\autotask\contracts.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

# Incremental on lastModifiedDateTime; set IMPERION_AUTOTASK_CONTRACT_SINCE_DAYS=0 for a full pull.
$sinceDays = if ($env:IMPERION_AUTOTASK_CONTRACT_SINCE_DAYS) { [int]$env:IMPERION_AUTOTASK_CONTRACT_SINCE_DAYS } else { 7 }

Get-ImperionAutotaskContract -SinceDays $sinceDays | Set-ImperionAutotaskContractToBronze
