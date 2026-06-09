function Get-ImperionMember {
    <#
    .SYNOPSIS
        Read a single named member from an object without throwing on absence (StrictMode-safe).
    .DESCRIPTION
        The module runs Set-StrictMode -Version Latest, under which referencing a non-existent
        property (`$obj.Missing`, even inside `if (...)`) THROWS. Every API-response paging
        wrapper needs to probe optional fields (`value`, `nextLink`, `@odata.nextLink`, `items`,
        `data`, `links`, …), so this returns the member value when present and $null when not.

        Unlike Get-ImperionPropertyPath this reads ONE member by its exact name (no dotted-path
        splitting), so it correctly handles property names that themselves contain a dot — most
        importantly Microsoft Graph's `@odata.nextLink`.
    .PARAMETER InputObject
        The object to read from (typically a parsed response body). $null yields $null.
    .PARAMETER Name
        The exact member name to read.
    .EXAMPLE
        $next = Get-ImperionMember $resp.Body '@odata.nextLink'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][AllowNull()] $InputObject,
        [Parameter(Mandatory, Position = 1)][string] $Name
    )
    if ($null -eq $InputObject) { return $null }
    $member = $InputObject.PSObject.Properties[$Name]
    if ($member) { $member.Value } else { $null }
}
