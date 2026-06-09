function Get-ImperionM365Device {
    <#
    .SYNOPSIS
        Collect Intune-managed devices for a tenant and flatten them to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6): mints a Graph token for the tenant (GDAP for customer
        tenants), pages /deviceManagement/managedDevices, and flattens each to the standard
        flat-table envelope (target bronze m365_devices). Returns rows; does not write. Requires
        Initialize-ImperionContext and DeviceManagementManagedDevices.Read.All.
    .PARAMETER TenantId
        Tenant to collect from; defaults to the partner tenant. Customer tenants use GDAP.
    .EXAMPLE
        Get-ImperionM365Device -TenantId $customerTenantId
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }

    $token = Get-ImperionGraphToken -TenantId $TenantId
    $devices = Invoke-ImperionGraphRequest -Uri 'https://graph.microsoft.com/v1.0/deviceManagement/managedDevices' -AccessToken $token

    $map = [ordered]@{
        device_name          = 'deviceName'
        managed_device_name  = 'managedDeviceName'
        os                   = 'operatingSystem'
        os_version           = 'osVersion'
        compliance_state     = 'complianceState'
        management_state     = 'managementState'
        manufacturer         = 'manufacturer'
        model                = 'model'
        serial_number        = 'serialNumber'
        imei                 = 'imei'
        wifi_mac_address     = 'wiFiMacAddress'
        user_principal_name  = 'userPrincipalName'
        user_display_name    = 'userDisplayName'
        email_address        = 'emailAddress'
        ownership            = 'managedDeviceOwnerType'
        enrolled_date_time   = 'enrolledDateTime'
        last_sync_date_time  = 'lastSyncDateTime'
        is_encrypted         = 'isEncrypted'
        device_category      = 'deviceCategoryDisplayName'
    }

    $devices | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'm365' -TenantId $TenantId -ExternalIdProperty 'id'
}
