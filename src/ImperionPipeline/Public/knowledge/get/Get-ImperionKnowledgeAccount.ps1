function Get-ImperionKnowledgeAccount {
    <#
    .SYNOPSIS
        Compose gold knowledge-object rows for every active silver account.
    .DESCRIPTION
        Get-layer composer for the gold tier (CLAUDE.md §6/§7, ADR-0009). Reads the silver
        `account` spine plus everything the agent should know about each account — its
        contact roster, open opportunities, Autotask contracts, and recent tickets (joined
        through the `autotask_companies` bronze link) — and composes ONE human-readable
        text body per account. The body is what gets chunked + embedded, so it is written
        the way a colleague would brief the agent, not as a data dump.

        Output rows are flat PSCustomObjects in the knowledge_object shape:
        tenant_id, entity_type='account', entity_ref (account id), title, body, summary,
        source='local-pipeline', metadata (counts), content_hash (over title+body — the
        idempotency key Set-ImperionKnowledgeObject and the vectorizer both honour).

        Read-only; pass -Connection to reuse one DB connection across the knowledge sync.
    .PARAMETER Connection
        Optional open Npgsql connection. When omitted, one is opened from config (ADR-0003
        short-lived token) and disposed before returning.
    .PARAMETER TenantId
        Owning tenant stamp. Defaults to the partner tenant (this is Imperion's own CRM data).
    .PARAMETER RecentTicketCount
        How many of the most recently active tickets to include per account. Default 10.
    .OUTPUTS
        Flat knowledge_object rows ready for Set-ImperionKnowledgeObject.
    .EXAMPLE
        Get-ImperionKnowledgeAccount | Set-ImperionKnowledgeObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        $Connection,
        [string] $TenantId,
        [ValidateRange(0, 100)][int] $RecentTicketCount = 10
    )

    if (-not $TenantId) { $TenantId = (Get-ImperionConfig).PartnerTenantId }

    $ownsConnection = $false
    $conn = $Connection
    if (-not $conn) { $conn = New-ImperionDbConnection; $ownsConnection = $true }
    try {
        $accounts = Invoke-ImperionDbQuery -Connection $conn -Sql @'
SELECT a.id::text AS id, a.name, a.relationship::text AS relationship,
       a.lifecycle_stage::text AS lifecycle_stage, a.health_score::text AS health_score
  FROM account a
 WHERE a.archived_at IS NULL
 ORDER BY a.name
'@
        if (-not $accounts) {
            Write-ImperionLog -Source 'knowledge' -Message 'knowledge accounts: no silver accounts found.'
            return @()
        }

        $contactsByAccount = @{}
        Invoke-ImperionDbQuery -Connection $conn -Sql @'
SELECT c.account_id::text AS account_id, c.full_name, c.title, c.email, c.crm_stage::text AS crm_stage
  FROM contact c
 WHERE c.account_id IS NOT NULL
 ORDER BY c.full_name
'@ | ForEach-Object {
            if (-not $contactsByAccount.ContainsKey($_.account_id)) {
                $contactsByAccount[$_.account_id] = [System.Collections.Generic.List[object]]::new()
            }
            $contactsByAccount[$_.account_id].Add($_)
        }

        $opportunitiesByAccount = @{}
        Invoke-ImperionDbQuery -Connection $conn -Sql @'
SELECT o.account_id::text AS account_id, o.name, o.sales_stage::text AS sales_stage
  FROM opportunity o
 ORDER BY o.name
'@ | ForEach-Object {
            if (-not $opportunitiesByAccount.ContainsKey($_.account_id)) {
                $opportunitiesByAccount[$_.account_id] = [System.Collections.Generic.List[object]]::new()
            }
            $opportunitiesByAccount[$_.account_id].Add($_)
        }

        $contractsByAccount = @{}
        Invoke-ImperionDbQuery -Connection $conn -Sql @'
SELECT ac.account_id::text AS account_id, c.contract_name, c.status, c.start_date, c.end_date
  FROM autotask_contracts c
  JOIN autotask_companies ac ON ac.external_ref = c.company_id
 WHERE ac.account_id IS NOT NULL
 ORDER BY c.contract_name
'@ | ForEach-Object {
            if (-not $contractsByAccount.ContainsKey($_.account_id)) {
                $contractsByAccount[$_.account_id] = [System.Collections.Generic.List[object]]::new()
            }
            $contractsByAccount[$_.account_id].Add($_)
        }

        $ticketsByAccount = @{}
        Invoke-ImperionDbQuery -Connection $conn -Sql @'
SELECT ac.account_id::text AS account_id, t.ticket_number, t.title, t.status, t.last_activity_date
  FROM autotask_tickets t
  JOIN autotask_companies ac ON ac.external_ref = t.company_id
 WHERE ac.account_id IS NOT NULL
 ORDER BY t.last_activity_date DESC NULLS LAST
'@ | ForEach-Object {
            if (-not $ticketsByAccount.ContainsKey($_.account_id)) {
                $ticketsByAccount[$_.account_id] = [System.Collections.Generic.List[object]]::new()
            }
            $ticketsByAccount[$_.account_id].Add($_)
        }

        $rows = foreach ($account in $accounts) {
            $accountContacts      = if ($contactsByAccount.ContainsKey($account.id)) { $contactsByAccount[$account.id] } else { @() }
            $accountOpportunities = if ($opportunitiesByAccount.ContainsKey($account.id)) { $opportunitiesByAccount[$account.id] } else { @() }
            $accountContracts     = if ($contractsByAccount.ContainsKey($account.id)) { $contractsByAccount[$account.id] } else { @() }
            $accountTickets       = if ($ticketsByAccount.ContainsKey($account.id)) { @($ticketsByAccount[$account.id])[0..([math]::Min($RecentTicketCount, @($ticketsByAccount[$account.id]).Count) - 1)] } else { @() }

            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add("Account: $($account.name)")
            $facts = @(
                if ($account.relationship)    { "relationship: $($account.relationship)" }
                if ($account.lifecycle_stage) { "lifecycle stage: $($account.lifecycle_stage)" }
                if ($account.health_score)    { "health score: $($account.health_score)" }
            )
            if ($facts) { $lines.Add(($facts -join ' · ')) }

            if (@($accountContacts).Count -gt 0) {
                $lines.Add('')
                $lines.Add("Contacts ($(@($accountContacts).Count)):")
                foreach ($contact in $accountContacts) {
                    $detail = @($contact.title, $contact.email, $contact.crm_stage) | Where-Object { $_ }
                    $lines.Add("- $($contact.full_name)$(if ($detail) { ' — ' + ($detail -join ' · ') })")
                }
            }
            if (@($accountOpportunities).Count -gt 0) {
                $lines.Add('')
                $lines.Add("Opportunities ($(@($accountOpportunities).Count)):")
                foreach ($opportunity in $accountOpportunities) {
                    $lines.Add("- $($opportunity.name) (stage: $($opportunity.sales_stage))")
                }
            }
            if (@($accountContracts).Count -gt 0) {
                $lines.Add('')
                $lines.Add("Autotask contracts ($(@($accountContracts).Count)):")
                foreach ($contract in $accountContracts) {
                    $span = @($contract.start_date, $contract.end_date) | Where-Object { $_ }
                    $lines.Add("- $($contract.contract_name) (status: $($contract.status)$(if ($span) { ', ' + ($span -join ' → ') }))")
                }
            }
            if (@($accountTickets).Count -gt 0) {
                $lines.Add('')
                $lines.Add("Recent tickets ($(@($accountTickets).Count) most recently active):")
                foreach ($ticket in $accountTickets) {
                    $lines.Add("- [$($ticket.ticket_number)] $($ticket.title) (status: $($ticket.status), last activity: $($ticket.last_activity_date))")
                }
            }

            $body = ($lines -join "`n").Trim()
            $row = [pscustomobject]@{
                tenant_id    = $TenantId
                entity_type  = 'account'
                entity_ref   = $account.id
                title        = $account.name
                body         = $body
                summary      = $null
                source       = 'local-pipeline'
                metadata     = (@{
                    contacts = @($accountContacts).Count; opportunities = @($accountOpportunities).Count
                    contracts = @($accountContracts).Count; recent_tickets = @($accountTickets).Count
                } | ConvertTo-Json -Compress)
                content_hash = $null
            }
            $row.content_hash = Get-ImperionContentHash -InputObject @{ title = $row.title; body = $row.body }
            $row
        }

        Write-ImperionLog -Source 'knowledge' -Message "knowledge accounts composed." -Data @{ accounts = @($rows).Count }
        return @($rows)
    }
    finally { if ($ownsConnection) { $conn.Dispose() } }
}
