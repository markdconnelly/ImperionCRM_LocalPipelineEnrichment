# m365/entra-group-members - daily Entra/M365 group membership expansion -> bronze
# (m365_group_members, issue #139 / front-end migration 0079 + issue #257).
# Cadence: Daily (scheduled-tasks/README.md) - membership is slow-changing; the
# change-detected upsert keeps re-runs cheap. Composes one get + one post; keep this short
# (CLAUDE.md §1). Auth is the module's cert-SP Graph token (GroupMember.Read.All, read-only);
# single-tenant against the Imperion company tenant by default - set IMPERION_M365_TENANT_IDS
# for fan-out (per-tenant isolation: each edge is stamped with its owning tenant).
#
# The membership edges reach the silver contact: member_external_id = m365_contacts.external_ref
# = the Entra user object id (front-end Directory-groups surface, #257). Pairs with the
# group-object task (entra-groups, issue #150).
#
# GATED: migration 0079 is applied to prod (2026-06-12); were m365_group_members ever absent
# the post fails loudly and the estate-sweep helper logs a Warn per tenant and continues so
# the schedule never crashes.
#
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion m365 entra-group-members' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\m365\entra-group-members.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

Invoke-ImperionM365EstateSweep -Label 'Entra group membership' -PerTenant {
    param($TenantId)
    if ($TenantId) { Get-ImperionM365GroupMember -TenantId $TenantId | Set-ImperionM365GroupMemberToBronze }
    else { Get-ImperionM365GroupMember | Set-ImperionM365GroupMemberToBronze }
}
