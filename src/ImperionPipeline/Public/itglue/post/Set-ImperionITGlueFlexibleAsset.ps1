function Set-ImperionITGlueFlexibleAsset {
    <#
    .SYNOPSIS
        Create or update an IT Glue flexible asset (the documentation hub write path, ADR-0006).
    .DESCRIPTION
        Resolves the flexible-asset-type id by name, finds an existing asset by a key trait
        (so re-runs update rather than duplicate), and POSTs/PATCHes the traits. Relationship
        traits are IT Glue "Tag" traits whose value is an array of related record ids
        (organizations, configurations, other flexible assets) — pass them in -Traits like
        any other trait. Type creation is a schema action and is gated behind
        -CreateTypeIfMissing.
    .PARAMETER ApiKey
        IT Glue API key (writer key from the SecretStore).
    .PARAMETER TypeName
        Flexible Asset Type name (e.g. 'Azure Service Principal').
    .PARAMETER OrganizationId
        IT Glue organization id the asset belongs to.
    .PARAMETER Traits
        Hashtable of trait-name -> value (tag traits take an array of ids).
    .PARAMETER MatchTrait
        Trait name used to dedupe (e.g. 'app-id' or 'azure-id').
    .PARAMETER MatchValue
        Expected value of MatchTrait for the existing asset.
    .PARAMETER CreateTypeIfMissing
        If set, create the flexible asset type when absent (requires -TypeFields).
    .PARAMETER TypeFields
        Field definitions used only when creating the type.
    .EXAMPLE
        Set-ImperionITGlueFlexibleAsset -ApiKey $k -TypeName 'Azure Service Principal' -OrganizationId 42 -MatchTrait 'app-id' -MatchValue $sp.appId -Traits $traits
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string] $ApiKey,
        [Parameter(Mandatory)][string] $TypeName,
        [Parameter(Mandatory)][int] $OrganizationId,
        [Parameter(Mandatory)][hashtable] $Traits,
        [Parameter(Mandatory)][string] $MatchTrait,
        [Parameter(Mandatory)][string] $MatchValue,
        [switch] $CreateTypeIfMissing,
        [object[]] $TypeFields
    )

    # 1. Resolve (or create) the flexible asset type by name.
    $types = Invoke-ImperionITGlueRequest -Path 'flexible_asset_types' -ApiKey $ApiKey -Query ("filter[name]={0}" -f [uri]::EscapeDataString($TypeName))
    $type = $types | Where-Object { (Get-ImperionPropertyPath -InputObject $_ -Path 'attributes.name') -eq $TypeName } | Select-Object -First 1
    if (-not $type) {
        if (-not $CreateTypeIfMissing) { throw "Flexible Asset Type '$TypeName' not found. Run setup with -CreateTypeIfMissing." }
        if (-not $TypeFields) { throw "Creating type '$TypeName' requires -TypeFields." }
        $createBody = @{ data = @{ type = 'flexible-asset-types'; attributes = @{ name = $TypeName; enabled = $true; 'flexible-asset-fields' = $TypeFields } } }
        if ($PSCmdlet.ShouldProcess($TypeName, 'Create IT Glue flexible asset type')) {
            $type = (Invoke-ImperionITGlueRequest -Path 'flexible_asset_types' -ApiKey $ApiKey -Method POST -Body $createBody).data
        }
    }
    $typeId = $type.id

    # 2. Find an existing asset for this org+type matching the key trait.
    $existing = Invoke-ImperionITGlueRequest -Path 'flexible_assets' -ApiKey $ApiKey -Query (
        "filter[flexible_asset_type_id]={0}&filter[organization_id]={1}&page[size]=1000" -f $typeId, $OrganizationId)
    $match = $existing | Where-Object { [string](Get-ImperionPropertyPath -InputObject $_ -Path "attributes.traits.$MatchTrait") -eq [string]$MatchValue } | Select-Object -First 1

    # 3. POST (create) or PATCH (update).
    $attributes = @{ 'organization-id' = $OrganizationId; 'flexible-asset-type-id' = [int]$typeId; traits = $Traits }
    if ($match) {
        $body = @{ data = @{ type = 'flexible-assets'; attributes = $attributes } }
        if ($PSCmdlet.ShouldProcess("$TypeName/$MatchValue", 'Update IT Glue flexible asset')) {
            $resp = Invoke-ImperionITGlueRequest -Path ("flexible_assets/{0}" -f $match.id) -ApiKey $ApiKey -Method PATCH -Body $body
            return $resp.data.id
        }
    }
    else {
        $body = @{ data = @{ type = 'flexible-assets'; attributes = $attributes } }
        if ($PSCmdlet.ShouldProcess("$TypeName/$MatchValue", 'Create IT Glue flexible asset')) {
            $resp = Invoke-ImperionITGlueRequest -Path 'flexible_assets' -ApiKey $ApiKey -Method POST -Body $body
            return $resp.data.id
        }
    }
}
