# posture/service-principals - daily Entra service-principal inventory.
# Cadence: Daily. Composes one cmdlet; keep this file short (CLAUDE.md section 1).
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion posture service-principals' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\posture\service-principals.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

# Set $env:IMPERION_ITGLUE_SP_ORG_ID to the IT Glue organization id to also document the
# service principals into IT Glue; leave it unset to land in Postgres bronze only.
if ($env:IMPERION_ITGLUE_SP_ORG_ID) {
    Invoke-ImperionServicePrincipalSync -OrganizationId ([int]$env:IMPERION_ITGLUE_SP_ORG_ID)
}
else {
    Invoke-ImperionServicePrincipalSync -SkipITGlue
}
