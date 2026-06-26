function Invoke-ImperionCustomSecurityAttributeSync {
    <#
    .SYNOPSIS
        Collect custom-security-attribute definitions into the custom_security_attribute_definitions bronze table (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/m365/custom-security-attributes.task.ps1. Fans out per consented tenant via
        Invoke-ImperionM365EstateSweep (IMPERION_M365_TENANT_IDS); each tenant's failure is isolated.
        Idempotent. Requires Initialize-ImperionContext.
    .EXAMPLE
        Invoke-ImperionCustomSecurityAttributeSync
    #>
    [CmdletBinding()]
    param([string] $TenantId)

    # -TenantId pins the sweep to one tenant (the tenant-outer driver, #359); no arg => the
    # registry-driven estate fan-out (#358). Forward only when supplied so the default is unchanged.
    $sweep = @{}
    if ($PSBoundParameters.ContainsKey('TenantId')) { $sweep.TenantId = $TenantId }
    Invoke-ImperionM365EstateSweep @sweep -Label 'Custom security attribute definitions' -PerTenant {
        param($TenantId)
        if ($TenantId) { Get-ImperionCustomSecurityAttribute -TenantId $TenantId | Set-ImperionCustomSecurityAttributeToBronze }
        else { Get-ImperionCustomSecurityAttribute | Set-ImperionCustomSecurityAttributeToBronze }
    }
}
