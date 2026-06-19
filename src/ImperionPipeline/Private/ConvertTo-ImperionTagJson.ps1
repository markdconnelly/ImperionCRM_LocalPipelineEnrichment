function ConvertTo-ImperionTagJson {
    <#
    .SYNOPSIS
        Serialize an Azure tags object ({name=value}) to a compact JSON string for a jsonb
        bronze column (private).
    .DESCRIPTION
        Azure resource/RG `tags` come back as an object whose properties are the tag keys.
        The cloud_* bronze tables (front-end migration 0130) store `tags` as **jsonb** — the
        real key→value map, not the flattened `k=v; …` string `ConvertTo-ImperionTagString`
        produces. This returns a compact JSON object string the bronze upsert binds with a
        `::jsonb` cast (`Set-ImperionCloudResourceToBronze -JsonColumns`), mirroring how
        `raw_payload` is written. StrictMode-safe and null-safe: returns `$null` (→ SQL NULL,
        a valid jsonb) when there are no tags.
    .PARAMETER Tags
        The ARM tags object (or $null).
    .EXAMPLE
        ConvertTo-ImperionTagJson ([pscustomobject]@{ env = 'prod' })   # -> {"env":"prod"}
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Position = 0)][AllowNull()] $Tags
    )
    if (-not $Tags) { return $null }
    # Depth 5 is ample — ARM tags are a flat string→string map.
    $Tags | ConvertTo-Json -Compress -Depth 5
}
