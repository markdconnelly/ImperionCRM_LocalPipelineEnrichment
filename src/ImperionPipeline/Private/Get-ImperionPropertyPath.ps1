function Get-ImperionPropertyPath {
    <#
    .SYNOPSIS
        Resolve a dotted property path against an object, returning $null on any missing hop.
    .DESCRIPTION
        Private helper for ConvertTo-ImperionFlatObject. Supports nested property access
        ('a.b.c'). If a hop is an array, it is left as-is for the caller to join. Never throws
        on a missing property (StrictMode-safe) — returns $null instead.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $InputObject,
        [Parameter(Mandatory)][string] $Path
    )
    $current = $InputObject
    foreach ($segment in ($Path -split '\.')) {
        if ($null -eq $current) { return $null }
        if ($current -is [System.Collections.IDictionary]) {
            $current = if ($current.Contains($segment)) { $current[$segment] } else { $null }
        }
        else {
            $prop = $current.PSObject.Properties[$segment]
            $current = if ($prop) { $prop.Value } else { $null }
        }
    }
    return $current
}

function Format-ImperionScalar {
    <#
    .SYNOPSIS
        Coerce a selected attribute value to its stable bronze-text form (private).
    .DESCRIPTION
        Bronze flat columns are text and lossless typing lives in raw_payload + silver. This
        normalizes a value for a flat cell: dates → ISO 8601 (PowerShell auto-converts ISO
        strings to [datetime], so we re-serialize deterministically), booleans → 'true'/'false',
        arrays → delimited (via Join-ImperionValues), nested objects → compact JSON, everything
        else → its string form. Null stays null.
    #>
    [CmdletBinding()]
    param([Parameter(ValueFromPipeline)] $Value)
    process {
        if ($null -eq $Value) { return $null }
        if ($Value -is [datetime]) { return $Value.ToString('o') }
        if ($Value -is [datetimeoffset]) { return $Value.ToString('o') }
        if ($Value -is [bool]) { return ([string]$Value).ToLowerInvariant() }
        if ($Value -is [string]) { return $Value }
        if ($Value -is [System.Collections.IEnumerable]) { return ($Value | Join-ImperionValues) }
        if ($Value -is [psobject] -and $Value.PSObject.Properties.Count -gt 0 -and $Value -isnot [ValueType]) {
            return ($Value | ConvertTo-Json -Compress -Depth 12)
        }
        return [string]$Value
    }
}
