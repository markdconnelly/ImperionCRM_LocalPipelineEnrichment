function Invoke-ImperionTelivyReportSync {
    <#
    .SYNOPSIS
        Pull Telivy reports into the televy_reports bronze table (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/telivy/assessments.task.ps1. Composes one get + one post; the Telivy API key is
        read from the SecretStore by the get function. Idempotent (televy_reports, ADR-0039 shape).
        Requires Initialize-ImperionContext; fails closed (the get function logs + exits) until the
        Telivy API key is provisioned.
    .EXAMPLE
        Invoke-ImperionTelivyReportSync
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    Get-ImperionTelivyReport | Set-ImperionTelivyReportToBronze
}
