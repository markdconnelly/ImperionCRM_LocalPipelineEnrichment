function Invoke-ImperionITGlueOrganizationSync {
    <#
    .SYNOPSIS
        Pull the IT Glue organization catalog into the itglue_companies bronze table (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/itglue/organizations.task.ps1. Composes one get + one post; the IT Glue read
        key comes from the SecretStore inside the get function. Idempotent (itglue_companies, ADR-0039
        shape). Requires Initialize-ImperionContext; fails closed (the get function logs + exits) until
        the IT Glue read key is provisioned.
    .EXAMPLE
        Invoke-ImperionITGlueOrganizationSync
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    Get-ImperionITGlueOrganization | Set-ImperionITGlueOrganizationToBronze
}
