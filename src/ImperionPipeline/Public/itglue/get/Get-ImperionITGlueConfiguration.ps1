function Get-ImperionITGlueConfiguration {
    <#
    .SYNOPSIS
        Collect IT Glue configurations (devices/assets) and flatten them to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6): pages /configurations (JSON:API) and flattens each
        record's attributes to the standard flat-table envelope. IT Glue configurations are the
        device/asset records — target: bronze itglue_devices / silver device. Returns rows; does
        not write. Requires Initialize-ImperionContext.
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant.
    .EXAMPLE
        Get-ImperionITGlueConfiguration
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }

    $apiKey = Resolve-ImperionITGlueApiKey
    $records = Invoke-ImperionITGlueRequest -Path 'configurations' -ApiKey $apiKey -Query 'sort=-updated-at&page[size]=1000' -BaseUri $cfg.ITGlue.BaseUri

    $map = [ordered]@{
        name                 = 'attributes.name'
        hostname             = 'attributes.hostname'
        configuration_type   = 'attributes.configuration-type-name'
        configuration_status = 'attributes.configuration-status-name'
        manufacturer         = 'attributes.manufacturer-name'
        model                = 'attributes.model-name'
        operating_system     = 'attributes.operating-system-name'
        serial_number        = 'attributes.serial-number'
        asset_tag            = 'attributes.asset-tag'
        primary_ip           = 'attributes.primary-ip'
        mac_address          = 'attributes.mac-address'
        organization_id      = 'attributes.organization-id'
        organization_name    = 'attributes.organization-name'
        contact_id           = 'attributes.contact-id'
        contact_name         = 'attributes.contact-name'
        installed_at         = 'attributes.installed-at'
        warranty_expires_at  = 'attributes.warranty-expires-at'
        created_at           = 'attributes.created-at'
        updated_at           = 'attributes.updated-at'
    }

    $records | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'itglue' -TenantId $TenantId -ExternalIdProperty 'id'
}
