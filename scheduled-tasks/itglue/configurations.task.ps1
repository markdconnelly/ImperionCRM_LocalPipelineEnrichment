# itglue/configurations - daily IT Glue configuration (device/asset) pull -> bronze
# (itglue_devices, ADR-0039 shape). Cadence: Daily (scheduled-tasks/README.md). Composes one
# get + one post; keep this short (CLAUDE.md §1). The IT Glue read key comes from the
# SecretStore inside the get function.
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion itglue configurations' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\itglue\configurations.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

Get-ImperionITGlueConfiguration | Set-ImperionITGlueConfigurationToBronze
