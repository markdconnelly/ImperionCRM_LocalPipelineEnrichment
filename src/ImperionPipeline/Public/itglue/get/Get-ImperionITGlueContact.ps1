function Get-ImperionITGlueContact {
    <#
    .SYNOPSIS
        Collect IT Glue contacts and flatten them to bronze-shaped [PSCustomObject] rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6): pages /contacts (JSON:API) and flattens each record's
        attributes to the standard flat-table envelope (the contact-emails array is collapsed to a
        delimited cell). Target: bronze itglue_contacts / silver contact. Returns rows; does not
        write. Requires Initialize-ImperionContext.
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant.
    .EXAMPLE
        Get-ImperionITGlueContact
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId
    )

    $cfg = Get-ImperionConfig
    $names = Get-ImperionSecretNames
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }

    $apiKey = Get-ImperionSecretValue -Name $names.ITGlueReadKey
    $records = Invoke-ImperionITGlueRequest -Path 'contacts' -ApiKey $apiKey -Query 'sort=-updated-at&page[size]=1000' -BaseUri $cfg.ITGlue.BaseUri

    $map = [ordered]@{
        name              = 'attributes.name'
        first_name        = 'attributes.first-name'
        last_name         = 'attributes.last-name'
        title             = 'attributes.title'
        organization_id   = 'attributes.organization-id'
        organization_name = 'attributes.organization-name'
        location_name     = 'attributes.location-name'
        emails            = { param($c) (@(Get-ImperionPropertyPath -InputObject $c -Path 'attributes.contact-emails') | Where-Object { $_ } | ForEach-Object { Get-ImperionMember $_ 'value' }) | Join-ImperionValues }
        important         = 'attributes.important'
        notes             = 'attributes.notes'
        created_at        = 'attributes.created-at'
        updated_at        = 'attributes.updated-at'
    }

    $records | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'itglue' -TenantId $TenantId -ExternalIdProperty 'id'
}
