function Invoke-ImperionEntraAppRegistrationSync {
    <#
    .SYNOPSIS
        Collect Entra app registrations into the entra_app_registrations bronze table (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/m365/entra-app-registrations.task.ps1. Fans out per consented tenant via
        Invoke-ImperionM365EstateSweep (IMPERION_M365_TENANT_IDS); each tenant's failure is isolated.
        Idempotent. Requires Initialize-ImperionContext.
    .EXAMPLE
        Invoke-ImperionEntraAppRegistrationSync
    #>
    [CmdletBinding()]
    param()

    Invoke-ImperionM365EstateSweep -Label 'Entra app-registrations' -PerTenant {
        param($TenantId)
        if ($TenantId) { Get-ImperionEntraAppRegistration -TenantId $TenantId | Set-ImperionEntraAppRegistrationToBronze }
        else { Get-ImperionEntraAppRegistration | Set-ImperionEntraAppRegistrationToBronze }
    }
}
