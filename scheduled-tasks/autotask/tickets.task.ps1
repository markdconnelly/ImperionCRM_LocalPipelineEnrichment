# autotask/tickets - frequent Autotask ticket reconcile -> bronze.
# Cadence: every 15-30 min (scheduled-tasks/README.md) — bulk catch-up; the cloud Pipeline
# handles real-time ticket webhooks. Composes one get + one post; keep this short (CLAUDE.md §1).
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion autotask tickets' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\autotask\tickets.task.ps1"' `
#     -Interval Minutes -IntervalValue 30

Import-Module ImperionPipeline
Initialize-ImperionContext

# Incremental on lastActivityDate; set IMPERION_AUTOTASK_TICKET_SINCE_DAYS=0 for a full pull.
$sinceDays = if ($env:IMPERION_AUTOTASK_TICKET_SINCE_DAYS) { [int]$env:IMPERION_AUTOTASK_TICKET_SINCE_DAYS } else { 1 }

Get-ImperionAutotaskTicket -SinceDays $sinceDays | Set-ImperionAutotaskTicketToBronze
