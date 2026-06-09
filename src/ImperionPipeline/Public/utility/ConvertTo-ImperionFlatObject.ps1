function ConvertTo-ImperionFlatObject {
    <#
    .SYNOPSIS
        Flatten a source record into a [PSCustomObject] holding only the attributes we care about.
    .DESCRIPTION
        The flat-table spine of the repo (CLAUDE.md §4/§6): every source pull is flattened to
        a table-shaped PSCustomObject that both documents into IT Glue and imports into
        Postgres unchanged. Pass a -PropertyMap (ordered hashtable) where each key is the
        output column name and each value is either a property path string (dotted) or a
        scriptblock receiving the source object as $_. The standard envelope columns
        (tenant_id, source, external_id, content_hash, collected_at, raw_payload) are added
        automatically.
    .PARAMETER InputObject
        The raw source record.
    .PARAMETER PropertyMap
        Ordered hashtable: outputColumn -> (path string | scriptblock).
    .PARAMETER Source
        Logical source key stamped onto the row.
    .PARAMETER TenantId
        Owning customer/partner tenant id (per-tenant isolation).
    .PARAMETER ExternalIdProperty
        Property/path on the source that is the stable external id.
    .EXAMPLE
        $sp | ConvertTo-ImperionFlatObject -Source m365 -TenantId $tid -ExternalIdProperty id -PropertyMap $map
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] $InputObject,
        [Parameter(Mandatory)][System.Collections.IDictionary] $PropertyMap,
        [Parameter(Mandatory)][string] $Source,
        [string] $TenantId,
        [Parameter(Mandatory)][string] $ExternalIdProperty,
        [string[]] $HashExclude = @('collected_at', 'content_hash', 'raw_payload')
    )
    process {
        $row = [ordered]@{}
        foreach ($column in $PropertyMap.Keys) {
            $selector = $PropertyMap[$column]
            $value = if ($selector -is [scriptblock]) {
                & $selector $InputObject
            }
            else {
                Get-ImperionPropertyPath -InputObject $InputObject -Path ([string]$selector)
            }
            # Bronze flat columns are text (lossless types stay in raw_payload). Coerce here so
            # PowerShell's auto-[datetime] conversion of ISO strings can't break a text insert.
            $row[$column] = Format-ImperionScalar -Value $value
        }

        $row['tenant_id']    = $TenantId
        $row['source']       = $Source
        $row['external_id']  = [string](Get-ImperionPropertyPath -InputObject $InputObject -Path $ExternalIdProperty)
        $row['collected_at'] = (Get-Date).ToString('o')
        $row['raw_payload']  = ($InputObject | ConvertTo-Json -Compress -Depth 20)

        $obj = [pscustomobject]$row
        $obj | Add-Member -NotePropertyName 'content_hash' -NotePropertyValue (
            $obj | Get-ImperionContentHash -ExcludeProperty $HashExclude
        ) -PassThru
    }
}
