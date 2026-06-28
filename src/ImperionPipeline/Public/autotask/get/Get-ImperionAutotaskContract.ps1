function Get-ImperionAutotaskContract {
    <#
    .SYNOPSIS
        Collect Autotask contracts and flatten them to bronze-shaped [PSCustomObject] rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6): pages the Contracts entity via the shared Autotask
        context and flattens each record to the standard flat-table envelope. Contracts are
        incremental on lastModifiedDateTime. Returns rows; does not write. Requires
        Initialize-ImperionContext.
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant.
    .PARAMETER SinceDays
        Incremental window on lastModifiedDateTime. Default 0 = full collection.
    .EXAMPLE
        Get-ImperionAutotaskContract -SinceDays 30
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId,
        [int] $SinceDays = 0
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.LocalTenantId }

    $ctx = Get-ImperionAutotaskContext
    $filter = if ($SinceDays -gt 0) {
        @{ op = 'gte'; field = 'lastModifiedDateTime'; value = (Get-Date).AddDays(-$SinceDays).ToString('yyyy-MM-ddTHH:mm:ssZ') }
    }
    else { @{ op = 'gte'; field = 'id'; value = 0 } }

    $records = Invoke-ImperionAutotaskRequest -ApiBaseUrl $ctx.ApiBase -Headers $ctx.Headers -Entity 'Contracts' -Filter $filter

    $map = [ordered]@{
        contract_name              = 'contractName'
        contract_number            = 'contractNumber'
        company_id                 = 'companyID'
        contact_id                 = 'contactID'
        contact_name               = 'contactName'
        contract_type              = 'contractType'
        contract_category          = 'contractCategory'
        status                     = 'status'
        billing_preference         = 'billingPreference'
        description                = 'description'
        start_date                 = 'startDate'
        end_date                   = 'endDate'
        estimated_cost             = 'estimatedCost'
        estimated_revenue          = 'estimatedRevenue'
        estimated_hours            = 'estimatedHours'
        setup_fee                  = 'setupFee'
        is_compliant               = 'isCompliant'
        is_default_contract        = 'isDefaultContract'
        opportunity_id             = 'opportunityID'
        purchase_order_number      = 'purchaseOrderNumber'
        service_level_agreement_id = 'serviceLevelAgreementID'
        last_modified_date_time    = 'lastModifiedDateTime'
    }

    $records | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'autotask' -TenantId $TenantId -ExternalIdProperty 'id'
}
