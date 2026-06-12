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

        Thin adapter over the knowledge-composer spine Invoke-ImperionKnowledgeCompose
        (#106): this declares the account SQL, the four related-roster queries
        (-RelatedQueries lookup caches), and the compose block; the spine owns the
        scaffold. Output rows are flat PSCustomObjects in the knowledge_object shape:
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

    # Captured under a name the spine's parameters cannot shadow when the compose
    # scriptblock resolves variables dynamically through the spine's scope (and so the
    # analyzer sees the parameter consumed outside the scriptblock).
    $recentTicketsToInclude = $RecentTicketCount

    $relatedQueries = @{
        contacts      = @{ KeyColumn = 'account_id'; Sql = @'
SELECT c.account_id::text AS account_id, c.full_name, c.title, c.email, c.crm_stage::text AS crm_stage
  FROM contact c
 WHERE c.account_id IS NOT NULL
 ORDER BY c.full_name
'@ }
        opportunities = @{ KeyColumn = 'account_id'; Sql = @'
SELECT o.account_id::text AS account_id, o.name, o.sales_stage::text AS sales_stage
  FROM opportunity o
 ORDER BY o.name
'@ }
        contracts     = @{ KeyColumn = 'account_id'; Sql = @'
SELECT ac.account_id::text AS account_id, c.contract_name, c.status, c.start_date, c.end_date
  FROM autotask_contracts c
  JOIN autotask_companies ac ON ac.external_ref = c.company_id
 WHERE ac.account_id IS NOT NULL
 ORDER BY c.contract_name
'@ }
        tickets       = @{ KeyColumn = 'account_id'; Sql = @'
SELECT ac.account_id::text AS account_id, t.ticket_number, t.title, t.status, t.last_activity_date
  FROM autotask_tickets t
  JOIN autotask_companies ac ON ac.external_ref = t.company_id
 WHERE ac.account_id IS NOT NULL
 ORDER BY t.last_activity_date DESC NULLS LAST
'@ }
    }

    Invoke-ImperionKnowledgeCompose -EntityType 'account' -Connection $Connection -TenantId $TenantId `
        -EmptyMessage 'knowledge accounts: no silver accounts found.' `
        -RelatedQueries $relatedQueries `
        -Query @'
SELECT a.id::text AS id, a.name, a.relationship::text AS relationship,
       a.lifecycle_stage::text AS lifecycle_stage, a.health_score::text AS health_score
  FROM account a
 WHERE a.archived_at IS NULL
 ORDER BY a.name
'@ -Compose {
        param($account, $related)
        $accountContacts      = if ($related['contacts'].ContainsKey($account.id)) { $related['contacts'][$account.id] } else { @() }
        $accountOpportunities = if ($related['opportunities'].ContainsKey($account.id)) { $related['opportunities'][$account.id] } else { @() }
        $accountContracts     = if ($related['contracts'].ContainsKey($account.id)) { $related['contracts'][$account.id] } else { @() }
        $accountTickets       = if ($related['tickets'].ContainsKey($account.id)) { @($related['tickets'][$account.id])[0..([math]::Min($recentTicketsToInclude, @($related['tickets'][$account.id]).Count) - 1)] } else { @() }

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

        [pscustomobject]@{
            entity_ref = $account.id
            title      = $account.name
            body       = ($lines -join "`n").Trim()
            source     = 'local-pipeline'
            metadata   = @{
                contacts = @($accountContacts).Count; opportunities = @($accountOpportunities).Count
                contracts = @($accountContracts).Count; recent_tickets = @($accountTickets).Count
            }
        }
    }
}
