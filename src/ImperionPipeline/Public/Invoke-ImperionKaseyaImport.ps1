function Invoke-ImperionKaseyaImport {
    <#
    .SYNOPSIS
        Bulk-load Kaseya-stack records (Autotask contracts + tickets, KQM proposals) into Postgres bronze.
    .DESCRIPTION
        Pure CRM/support data: flattens straight to Postgres, skipping the IT Glue hub
        (ADR-0006), with change-detecting upserts. Autotask field names are CONFIRMED against
        the live field-metadata API (companies use `companyID`; contracts sync on
        `lastModifiedDateTime`, tickets on `lastActivityDate`). Auth resolves the account zone
        then pages `/{Entity}/query?search=` (matching the cloud Pipeline client). Autotask
        ticket webhooks stay in the cloud Pipeline (ADR-0001); this is the scheduled bulk poll.
        Requires Initialize-ImperionContext.
    .PARAMETER Entity
        All (default), Proposals, Contracts, or Tickets.
    .PARAMETER SinceDays
        Incremental window where supported. Default 0 = full load.
    .EXAMPLE
        Invoke-ImperionKaseyaImport -Entity Tickets -SinceDays 7
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('All', 'Proposals', 'Contracts', 'Tickets')][string] $Entity = 'All',
        [int] $SinceDays = 0
    )

    $cfg = Get-ImperionConfig
    $names = Get-ImperionSecretNames
    $tenantId = $cfg.PartnerTenantId
    $started = Get-Date

    # Resolve Autotask auth + zone once (only when an Autotask entity is requested).
    $atHeaders = $null; $apiBase = $null
    if ($Entity -in 'All', 'Contracts', 'Tickets') {
        $atUser = Get-ImperionSecretValue -Name $names.AutotaskUserName
        $atHeaders = @{
            ApiIntegrationCode = (Get-ImperionSecretValue -Name $names.AutotaskIntegrationCode)
            UserName           = $atUser
            Secret             = (Get-ImperionSecretValue -Name $names.AutotaskSecret)
            'Content-Type'     = 'application/json'
        }
        $zone = (Invoke-ImperionRestWithRetry -Uri "https://webservices.autotask.net/atservicesrest/v1.0/zoneInformation?user=$([uri]::EscapeDataString($atUser))" -Headers $atHeaders -Method GET).Body
        if (-not $zone.url) { throw 'Autotask zoneInformation returned no url.' }
        $apiBase = ($zone.url.TrimEnd('/')) + '/V1.0'
    }

    function Get-AutotaskRecords {
        param([string] $EntityName, [string] $SinceField)
        $filter = if ($SinceDays -gt 0 -and $SinceField) {
            @(@{ op = 'gte'; field = $SinceField; value = (Get-Date).AddDays(-$SinceDays).ToString('yyyy-MM-ddTHH:mm:ssZ') })
        }
        else { @(@{ op = 'gte'; field = 'id'; value = 0 }) }
        $search = (@{ filter = $filter } | ConvertTo-Json -Depth 6 -Compress)
        $items = [System.Collections.Generic.List[object]]::new()
        $next = "$apiBase/$EntityName/query?search=$([uri]::EscapeDataString($search))"
        while ($next) {
            $resp = Invoke-ImperionRestWithRetry -Uri $next -Headers $atHeaders -Method GET
            if ($resp.Body.items) { $resp.Body.items | ForEach-Object { $items.Add($_) } }
            $next = $resp.Body.pageDetails.nextPageUrl
        }
        return $items.ToArray()
    }

    $conn = New-ImperionDbConnection

    function Save-Kaseya {
        param($Items, [System.Collections.IDictionary] $Map, [string] $Source, [string] $Table, [string] $ExternalIdProperty = 'id')
        if (-not $Items -or @($Items).Count -eq 0) { Write-ImperionLog -Source $Source -Message "${Table}: 0 items."; return }
        $flat = $Items | ConvertTo-ImperionFlatObject -PropertyMap $Map -Source $Source -TenantId $tenantId -ExternalIdProperty $ExternalIdProperty
        $tally = Invoke-ImperionBronzeUpsert -Connection $conn -Table $Table -Rows $flat
        Write-ImperionLog -Level Metric -Source $Source -Message "$Table loaded." -Data @{ scanned = $tally.scanned; inserted = $tally.inserted; updated = $tally.updated; unchanged = $tally.unchanged }
    }

    try {
        if ($Entity -in 'All', 'Contracts') {
            $contracts = Get-AutotaskRecords -EntityName 'Contracts' -SinceField 'lastModifiedDateTime'
            Save-Kaseya -Items $contracts -Source 'autotask' -Table 'autotask_contracts' -Map ([ordered]@{
                contract_name = 'contractName'; contract_number = 'contractNumber'; company_id = 'companyID'
                contact_id = 'contactID'; contact_name = 'contactName'; contract_type = 'contractType'
                contract_category = 'contractCategory'; status = 'status'; billing_preference = 'billingPreference'
                description = 'description'; start_date = 'startDate'; end_date = 'endDate'
                estimated_cost = 'estimatedCost'; estimated_revenue = 'estimatedRevenue'; estimated_hours = 'estimatedHours'
                setup_fee = 'setupFee'; is_compliant = 'isCompliant'; is_default_contract = 'isDefaultContract'
                opportunity_id = 'opportunityID'; purchase_order_number = 'purchaseOrderNumber'
                service_level_agreement_id = 'serviceLevelAgreementID'; last_modified_date_time = 'lastModifiedDateTime'
            })
        }
        if ($Entity -in 'All', 'Tickets') {
            $tickets = Get-AutotaskRecords -EntityName 'Tickets' -SinceField 'lastActivityDate'
            Save-Kaseya -Items $tickets -Source 'autotask' -Table 'autotask_tickets' -Map ([ordered]@{
                ticket_number = 'ticketNumber'; title = 'title'; status = 'status'; priority = 'priority'; company_id = 'companyID'
                contact_id = 'contactID'; contract_id = 'contractID'; queue_id = 'queueID'; issue_type = 'issueType'
                sub_issue_type = 'subIssueType'; ticket_type = 'ticketType'; ticket_category = 'ticketCategory'
                assigned_resource_id = 'assignedResourceID'; creator_resource_id = 'creatorResourceID'; create_date = 'createDate'
                due_date_time = 'dueDateTime'; completed_date = 'completedDate'; resolved_date_time = 'resolvedDateTime'
                first_response_date_time = 'firstResponseDateTime'; last_activity_date = 'lastActivityDate'
                last_tracked_modification_date_time = 'lastTrackedModificationDateTime'; description = 'description'
                resolution = 'resolution'; ticket_source = 'source'
            })
        }
        if ($Entity -in 'All', 'Proposals') {
            # KQM (Kaseya Quote Manager) — shape is an ASSUMPTION (no live access yet).
            $kqmBase = Get-ImperionSecretValue -Name $names.KqmBaseUri
            $kqmKey = Get-ImperionSecretValue -Name $names.KqmApiKey
            $resp = Invoke-ImperionRestWithRetry -Uri "$($kqmBase.TrimEnd('/'))/quotes" -Headers @{ Authorization = "Bearer $kqmKey" } -Method GET
            $proposals = if ($resp.Body.data) { $resp.Body.data } else { $resp.Body }
            Save-Kaseya -Items $proposals -Source 'kqm' -Table 'kqm_proposals' -Map ([ordered]@{
                name = 'name'; status = 'status'; total = 'total'; account_ref = 'accountId'; created_at = 'createdAt'; updated_at = 'updatedAt'
            })
        }
    }
    finally { $conn.Dispose() }

    Write-ImperionLog -Level Metric -Source 'kaseya' -Message 'Kaseya bulk load complete.' -Data @{ entity = $Entity; seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 1) }
}
