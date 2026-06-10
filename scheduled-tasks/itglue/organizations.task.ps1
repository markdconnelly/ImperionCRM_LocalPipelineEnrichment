# itglue/organizations - daily IT Glue organization pull -> bronze (itglue_companies, ADR-0039 shape).
# Cadence: Daily (scheduled-tasks/README.md). Composes one get + one post; keep this short
# (CLAUDE.md §1). The IT Glue read key comes from the SecretStore inside the get function.
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion itglue organizations' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\itglue\organizations.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

Get-ImperionITGlueOrganization | Set-ImperionITGlueOrganizationToBronze
