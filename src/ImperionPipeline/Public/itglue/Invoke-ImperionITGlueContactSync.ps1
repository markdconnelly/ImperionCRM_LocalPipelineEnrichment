function Invoke-ImperionITGlueContactSync {
    <#
    .SYNOPSIS
        Pull the IT Glue contact catalog into the itglue_contacts bronze table (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/itglue/contacts.task.ps1. Composes one get + one post; the IT Glue read key
        comes from the SecretStore inside the get function. Idempotent (itglue_contacts, ADR-0039
        shape). Requires Initialize-ImperionContext; fails closed (the get function logs + exits) until
        the IT Glue read key is provisioned.
    .EXAMPLE
        Invoke-ImperionITGlueContactSync
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    Get-ImperionITGlueContact | Set-ImperionITGlueContactToBronze
}
