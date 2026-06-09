function ConvertTo-ImperionTagString {
    <#
    .SYNOPSIS
        Flatten an Azure tags object ({name=value}) to a stable 'k=v; k=v' string (private).
    .DESCRIPTION
        Azure resource/RG tags come back as an object whose properties are the tag keys. This
        collapses them to one flat-table cell. StrictMode-safe and null-safe (returns $null when
        there are no tags). Used by the azure get-layer collectors.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Position = 0)][AllowNull()] $Tags
    )
    if (-not $Tags) { return $null }
    ($Tags.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join '; '
}
