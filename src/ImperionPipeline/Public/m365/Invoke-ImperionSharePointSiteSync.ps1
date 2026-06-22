function Invoke-ImperionSharePointSiteSync {
    <#
    .SYNOPSIS
        Collect SharePoint site inventory into the sharepoint_sites bronze table (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/m365/sharepoint-sites.task.ps1. Fans out per consented tenant via
        Invoke-ImperionM365EstateSweep (IMPERION_M365_TENANT_IDS); each tenant's failure is isolated.
        Idempotent. Requires Initialize-ImperionContext.
    .EXAMPLE
        Invoke-ImperionSharePointSiteSync
    #>
    [CmdletBinding()]
    param()

    Invoke-ImperionM365EstateSweep -Label 'SharePoint site inventory' -PerTenant {
        param($TenantId)
        if ($TenantId) { Get-ImperionSharePointSite -TenantId $TenantId | Set-ImperionSharePointSiteToBronze }
        else { Get-ImperionSharePointSite | Set-ImperionSharePointSiteToBronze }
    }
}
