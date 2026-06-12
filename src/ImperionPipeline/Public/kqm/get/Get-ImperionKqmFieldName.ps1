function Get-ImperionKqmFieldName {
    <#
    .SYNOPSIS
        Live-shape verification probe: dump KQM response FIELD NAMES (never values).
    .DESCRIPTION
        Issue #98 gates the KQM collector on verifying the live response shape — the
        public docs name the endpoints but not their fields. This probe pulls ONE page of
        the chosen endpoint and emits one row per discovered field: its name, .NET type,
        and how many of the sampled records carry a non-null value. Field VALUES are
        never emitted, logged, or written anywhere — quotes contain client commercial
        data and the probe output is safe to paste into an issue.

        Operator loop: run the probe → compare against the assumed map in
        Get-ImperionKqmProposal (and the kqm_proposals columns, front-end migration
        0038) → correct the map / propose a migration in the front-end repo if the real
        shape diverges. Requires Initialize-ImperionContext.
    .PARAMETER Endpoint
        KQM resource to probe: quote (default), salesorder, supplier, or warehouse.
    .PARAMETER BaseUri
        KQM REST base. Default 'https://api.kaseyaquotemanager.com/v1'.
    .PARAMETER SampleSize
        How many records from the first page to inspect. Default 25.
    .PARAMETER ApiKey
        KQM API key override. Defaults to the SecretStore/Key Vault resolution.
    .OUTPUTS
        [pscustomobject] rows { Endpoint; Field; Type; NonNullOfSample; SampleSize }.
    .EXAMPLE
        Get-ImperionKqmFieldName -Endpoint quote | Format-Table
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [ValidateSet('quote', 'salesorder', 'supplier', 'warehouse')][string] $Endpoint = 'quote',
        [string] $BaseUri = 'https://api.kaseyaquotemanager.com/v1',
        [ValidateRange(1, 100)][int] $SampleSize = 25,
        [string] $ApiKey
    )

    $ApiKey = Resolve-ImperionKqmApiKey -ApiKey $ApiKey
    $uri = '{0}/{1}' -f $BaseUri.TrimEnd('/'), $Endpoint
    # One page only: PageSize 100 means any first page short of 100 ends the loop; MaxPages 1 hard-caps it.
    $records = @(Invoke-ImperionKqmRequest -ApiKey $ApiKey -Uri $uri -MaxPages 1 | Select-Object -First $SampleSize)

    if ($records.Count -eq 0) {
        Write-ImperionLog -Level Warn -Source 'kqm' -Message "Field probe: $Endpoint returned no records."
        return
    }

    $fieldTally = [ordered]@{}
    foreach ($record in $records) {
        foreach ($property in $record.PSObject.Properties) {
            if (-not $fieldTally.Contains($property.Name)) {
                $fieldTally[$property.Name] = [pscustomobject]@{ Type = $null; NonNull = 0 }
            }
            if ($null -ne $property.Value) {
                $fieldTally[$property.Name].NonNull++
                if (-not $fieldTally[$property.Name].Type) {
                    $fieldTally[$property.Name].Type = $property.Value.GetType().Name
                }
            }
        }
    }

    Write-ImperionLog -Source 'kqm' -Message "Field probe: $Endpoint exposed $($fieldTally.Count) fields across $($records.Count) sampled records."
    foreach ($fieldName in ($fieldTally.Keys | Sort-Object)) {
        [pscustomobject]@{
            Endpoint        = $Endpoint
            Field           = $fieldName
            Type            = $fieldTally[$fieldName].Type
            NonNullOfSample = $fieldTally[$fieldName].NonNull
            SampleSize      = $records.Count
        }
    }
}
