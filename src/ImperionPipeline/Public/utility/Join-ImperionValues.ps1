function Join-ImperionValues {
    <#
    .SYNOPSIS
        Join an array of scalars into a delimited string for flat-table storage; pass scalars through.
    .DESCRIPTION
        Used in property-map scriptblocks (e.g. $sp.replyUrls | Join-ImperionValues) to collapse
        multi-valued source fields into a single flat-table cell. Public so scripts can call it
        from their selectors.
    .PARAMETER Value
        The value (array or scalar) to flatten.
    .PARAMETER Delimiter
        Separator for array elements. Default '; '.
    .EXAMPLE
        @('a','b') | Join-ImperionValues   # -> 'a; b'
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(ValueFromPipeline)] $Value,
        [string] $Delimiter = '; '
    )
    # Accumulate across the pipeline so both `$arr | Join-ImperionValues` (unrolled per
    # element) and `Join-ImperionValues -Value $arr` (one array) produce the same result.
    begin { $accumulated = [System.Collections.Generic.List[object]]::new() }
    process {
        if ($null -eq $Value) { return }
        foreach ($item in $Value) { $accumulated.Add($item) }  # a string is added whole, not per-char
    }
    end {
        if ($accumulated.Count -eq 0) { return $null }
        ($accumulated | ForEach-Object { [string]$_ }) -join $Delimiter
    }
}
