function Invoke-ImperionITGlueConfigurationSync {
    <#
    .SYNOPSIS
        Pull the IT Glue configuration (device/asset) catalog into the itglue_devices bronze table (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/itglue/configurations.task.ps1. Composes one get + one post; the IT Glue read
        key comes from the SecretStore inside the get function. Idempotent (itglue_devices, ADR-0039
        shape). Requires Initialize-ImperionContext; fails closed (the get function logs + exits) until
        the IT Glue read key is provisioned.
    .EXAMPLE
        Invoke-ImperionITGlueConfigurationSync
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    Get-ImperionITGlueConfiguration | Set-ImperionITGlueConfigurationToBronze
}
