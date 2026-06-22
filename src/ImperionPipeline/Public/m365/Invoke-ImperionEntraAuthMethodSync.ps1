function Invoke-ImperionEntraAuthMethodSync {
    <#
    .SYNOPSIS
        Collect per-user MFA registration into the entra_auth_methods bronze table (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/m365/auth-methods.task.ps1. Fans out per consented tenant via
        Invoke-ImperionM365EstateSweep (IMPERION_M365_TENANT_IDS); each tenant's failure is isolated.
        Idempotent. Requires Initialize-ImperionContext.
    .EXAMPLE
        Invoke-ImperionEntraAuthMethodSync
    #>
    [CmdletBinding()]
    param()

    Invoke-ImperionM365EstateSweep -Label 'Entra auth-methods' -PerTenant {
        param($TenantId)
        if ($TenantId) { Get-ImperionEntraAuthMethod -TenantId $TenantId | Set-ImperionEntraAuthMethodToBronze }
        else { Get-ImperionEntraAuthMethod | Set-ImperionEntraAuthMethodToBronze }
    }
}
