function Get-ImperionContentHash {
    <#
    .SYNOPSIS
        Compute a stable SHA-256 hash over the meaningful attributes of a record.
    .DESCRIPTION
        Change detection (docs/operations/change-detection.md) depends on a hash that is
        stable across runs and ignores volatile fields. The input object's properties are
        canonicalized (sorted by name, optional exclusions removed) and serialized to JSON
        before hashing, so property order never affects the result.
    .PARAMETER InputObject
        The flattened record (PSCustomObject / hashtable) to hash.
    .PARAMETER ExcludeProperty
        Property names to exclude (e.g. collected_at, etag, lastSeen) so volatility doesn't
        cause false "changed" results.
    .EXAMPLE
        $hash = $flat | Get-ImperionContentHash -ExcludeProperty collected_at, raw_payload
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] $InputObject,
        [string[]] $ExcludeProperty = @('collected_at', 'content_hash', 'raw_payload')
    )
    process {
        $map = [ordered]@{}
        $props = if ($InputObject -is [hashtable]) { $InputObject.Keys } else { $InputObject.PSObject.Properties.Name }
        foreach ($name in ($props | Sort-Object)) {
            if ($ExcludeProperty -contains $name) { continue }
            $value = if ($InputObject -is [hashtable]) { $InputObject[$name] } else { $InputObject.$name }
            $map[$name] = $value
        }
        $canonical = $map | ConvertTo-Json -Compress -Depth 12
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($canonical)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            -join ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') })
        }
        finally { $sha.Dispose() }
    }
}
