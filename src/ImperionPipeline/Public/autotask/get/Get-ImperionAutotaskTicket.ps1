function Get-ImperionAutotaskTicket {
    <#
    .SYNOPSIS
        Collect Autotask tickets and flatten them to bronze-shaped [PSCustomObject] rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6): pages the Tickets entity via the shared Autotask
        context and flattens each record to the standard flat-table envelope. Tickets are
        incremental on lastActivityDate. This is the scheduled BULK poll; real-time ticket
        webhooks stay in the cloud Pipeline (ADR-0001). Returns rows; does not write. Requires
        Initialize-ImperionContext.
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant.
    .PARAMETER SinceDays
        Incremental window on lastActivityDate. Default 0 = full collection.
    .EXAMPLE
        Get-ImperionAutotaskTicket -SinceDays 1
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId,
        [int] $SinceDays = 0
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }

    $ctx = Get-ImperionAutotaskContext
    $filter = if ($SinceDays -gt 0) {
        @{ op = 'gte'; field = 'lastActivityDate'; value = (Get-Date).AddDays(-$SinceDays).ToString('yyyy-MM-ddTHH:mm:ssZ') }
    }
    else { @{ op = 'gte'; field = 'id'; value = 0 } }

    $records = Invoke-ImperionAutotaskRequest -ApiBaseUrl $ctx.ApiBase -Headers $ctx.Headers -Entity 'Tickets' -Filter $filter

    $map = [ordered]@{
        ticket_number                       = 'ticketNumber'
        title                               = 'title'
        status                              = 'status'
        priority                            = 'priority'
        company_id                          = 'companyID'
        contact_id                          = 'contactID'
        contract_id                         = 'contractID'
        queue_id                            = 'queueID'
        issue_type                          = 'issueType'
        sub_issue_type                      = 'subIssueType'
        ticket_type                         = 'ticketType'
        ticket_category                     = 'ticketCategory'
        assigned_resource_id                = 'assignedResourceID'
        creator_resource_id                 = 'creatorResourceID'
        create_date                         = 'createDate'
        due_date_time                       = 'dueDateTime'
        completed_date                      = 'completedDate'
        resolved_date_time                  = 'resolvedDateTime'
        first_response_date_time            = 'firstResponseDateTime'
        last_activity_date                  = 'lastActivityDate'
        last_tracked_modification_date_time = 'lastTrackedModificationDateTime'
        description                         = 'description'
        resolution                          = 'resolution'
        ticket_source                       = 'source'
    }

    $records | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'autotask' -TenantId $TenantId -ExternalIdProperty 'id'
}
