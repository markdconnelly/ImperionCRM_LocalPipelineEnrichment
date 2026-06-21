# m365/custom-security-attributes - daily custom-security-attribute DEFINITION pull -> bronze
# (custom_security_attribute_definitions, issue #141 / front-end schema issue ImperionCRM#259).
# Cadence: Daily (scheduled-tasks/README.md) - the attribute taxonomy is slow-changing; the
# change-detected upsert keeps re-runs cheap. Composes one get + one post; keep this short
# (CLAUDE.md §1). Auth is the module's cert-SP Graph token
# (CustomSecAttributeDefinition.Read.All, read-only, part of the read-only-by-default grant);
# single-tenant against the Imperion company tenant by default - set IMPERION_M365_TENANT_IDS
# for GDAP fan-out (per-tenant isolation: each row is stamped with its owning tenant).
# DEFINITIONS only - per-principal assignments (CustomSecAttributeAssignment.Read.All) are a
# heavier PII-bearing surface deferred to a follow-up (docs/integrations/information-protection.md).
#
# GATED: until the front-end custom_security_attribute_definitions migration (#259) is applied
# to prod the post fails loudly; the estate-sweep helper logs a Warn per tenant and continues
# so the schedule never crashes.
#
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion m365 custom-security-attributes' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\m365\custom-security-attributes.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

Invoke-ImperionM365EstateSweep -Label 'Custom security attribute definitions' -PerTenant {
    param($TenantId)
    if ($TenantId) { Get-ImperionCustomSecurityAttribute -TenantId $TenantId | Set-ImperionCustomSecurityAttributeToBronze }
    else { Get-ImperionCustomSecurityAttribute | Set-ImperionCustomSecurityAttributeToBronze }
}
