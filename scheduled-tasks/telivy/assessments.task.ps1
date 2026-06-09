# telivy/assessments - daily Telivy report pull -> bronze (televy_reports, ADR-0039 shape).
# Cadence: Daily (scheduled-tasks/README.md). Composes one get + one post; keep this short
# (CLAUDE.md §1). The Telivy API key is read from the SecretStore by the get function.
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion telivy assessments' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\telivy\assessments.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

Get-ImperionTelivyReport | Set-ImperionTelivyReportToBronze
