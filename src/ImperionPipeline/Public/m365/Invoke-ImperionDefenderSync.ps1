function Invoke-ImperionDefenderSync {
    <#
    .SYNOPSIS
        Collect Defender XDR incidents + alerts into the defender bronze tables (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/m365/defender.task.ps1. Fans out per consented tenant via
        Invoke-ImperionM365EstateSweep (IMPERION_M365_TENANT_IDS); each tenant's failure is isolated.
        Idempotent. Requires Initialize-ImperionContext.
    .EXAMPLE
        Invoke-ImperionDefenderSync
    #>
    [CmdletBinding()]
    param()

    Invoke-ImperionM365EstateSweep -Source 'defender' -Label 'Defender XDR' -PerTenant {
        param($TenantId)
        if ($TenantId) { Get-ImperionDefenderObject -TenantId $TenantId | Set-ImperionDefenderToBronze }
        else { Get-ImperionDefenderObject | Set-ImperionDefenderToBronze }
    }
}
