function Invoke-ImperionSensitivityLabelSync {
    <#
    .SYNOPSIS
        Collect information-protection sensitivity labels into the sensitivity_labels bronze table (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/m365/sensitivity-labels.task.ps1. Fans out per consented tenant via
        Invoke-ImperionM365EstateSweep (IMPERION_M365_TENANT_IDS); each tenant's failure is isolated.
        Idempotent. Requires Initialize-ImperionContext.
    .EXAMPLE
        Invoke-ImperionSensitivityLabelSync
    #>
    [CmdletBinding()]
    param()

    Invoke-ImperionM365EstateSweep -Label 'Sensitivity labels' -PerTenant {
        param($TenantId)
        if ($TenantId) { Get-ImperionSensitivityLabel -TenantId $TenantId | Set-ImperionSensitivityLabelToBronze }
        else { Get-ImperionSensitivityLabel | Set-ImperionSensitivityLabelToBronze }
    }
}
