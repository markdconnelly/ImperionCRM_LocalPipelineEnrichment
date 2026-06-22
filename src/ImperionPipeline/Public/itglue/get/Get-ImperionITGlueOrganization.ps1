function Get-ImperionITGlueOrganization {
    <#
    .SYNOPSIS
        Collect IT Glue organizations and flatten them to bronze-shaped [PSCustomObject] rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6): reads the IT Glue API key from the SecretStore, pages
        /organizations (JSON:API), and flattens each record's attributes to the standard
        flat-table envelope (target: bronze itglue_companies / silver account). Returns rows; does
        not write. Requires Initialize-ImperionContext.
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant.
    .EXAMPLE
        Get-ImperionITGlueOrganization
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }

    $apiKey = Resolve-ImperionITGlueApiKey
    $records = Invoke-ImperionITGlueRequest -Path 'organizations' -ApiKey $apiKey -Query 'sort=-updated-at&page[size]=1000' -BaseUri $cfg.ITGlue.BaseUri

    $map = [ordered]@{
        name                = 'attributes.name'
        organization_type   = 'attributes.organization-type-name'
        organization_status = 'attributes.organization-status-name'
        description         = 'attributes.description'
        primary_domain      = 'attributes.primary-domain'
        logo                = 'attributes.logo'
        quick_notes         = 'attributes.quick-notes'
        created_at          = 'attributes.created-at'
        updated_at          = 'attributes.updated-at'
    }

    $records | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'itglue' -TenantId $TenantId -ExternalIdProperty 'id'
}
