function Get-ImperionKnowledgeTicket {
    <#
    .SYNOPSIS
        Compose gold knowledge-object rows for every Autotask ticket in bronze.
    .DESCRIPTION
        Get-layer composer for the gold tier (CLAUDE.md §6/§7, ADR-0009). Tickets are the
        support-side memory: each gets its own knowledge object (number, title, status,
        classification, dates, full description, resolution) so the agent can answer
        "what happened with X" from per-ticket retrieval, not just the account roll-up.
        Reads the `autotask_tickets` bronze joined through `autotask_companies` to the
        owning silver account. Long descriptions/resolutions are handled downstream by
        the chunker.

        Output rows are flat PSCustomObjects in the knowledge_object shape
        (entity_type='ticket', entity_ref = the Autotask ticket id). Read-only;
        pass -Connection to reuse one DB connection across the knowledge sync.
    .PARAMETER Connection
        Optional open Npgsql connection. When omitted, one is opened from config and
        disposed before returning.
    .PARAMETER TenantId
        Owning tenant stamp. Defaults to the partner tenant.
    .OUTPUTS
        Flat knowledge_object rows ready for Set-ImperionKnowledgeObject.
    .EXAMPLE
        Get-ImperionKnowledgeTicket | Set-ImperionKnowledgeObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        $Connection,
        [string] $TenantId
    )

    if (-not $TenantId) { $TenantId = (Get-ImperionConfig).PartnerTenantId }

    $ownsConnection = $false
    $conn = $Connection
    if (-not $conn) { $conn = New-ImperionDbConnection; $ownsConnection = $true }
    try {
        $tickets = Invoke-ImperionDbQuery -Connection $conn -Sql @'
SELECT t.external_id, t.ticket_number, t.title, t.status, t.priority, t.issue_type,
       t.sub_issue_type, t.ticket_type, t.create_date, t.completed_date,
       t.last_activity_date, t.description, t.resolution, a.name AS account_name
  FROM autotask_tickets t
  LEFT JOIN autotask_companies ac ON ac.external_ref = t.company_id
  LEFT JOIN account a ON a.id = ac.account_id
 ORDER BY t.last_activity_date DESC NULLS LAST
'@
        if (-not $tickets) {
            Write-ImperionLog -Source 'knowledge' -Message 'knowledge tickets: no autotask_tickets bronze found.'
            return @()
        }

        $rows = foreach ($ticket in $tickets) {
            $title = if ($ticket.title) { "[$($ticket.ticket_number)] $($ticket.title)" } else { "Ticket $($ticket.ticket_number)" }
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add("Ticket: $title")
            if ($ticket.account_name) { $lines.Add("Account: $($ticket.account_name)") }
            $facts = @(
                if ($ticket.status)         { "status: $($ticket.status)" }
                if ($ticket.priority)       { "priority: $($ticket.priority)" }
                if ($ticket.ticket_type)    { "type: $($ticket.ticket_type)" }
                if ($ticket.issue_type)     { "issue: $($ticket.issue_type)" }
                if ($ticket.sub_issue_type) { "sub-issue: $($ticket.sub_issue_type)" }
            )
            if ($facts) { $lines.Add(($facts -join ' · ')) }
            $dates = @(
                if ($ticket.create_date)        { "created: $($ticket.create_date)" }
                if ($ticket.completed_date)     { "completed: $($ticket.completed_date)" }
                if ($ticket.last_activity_date) { "last activity: $($ticket.last_activity_date)" }
            )
            if ($dates) { $lines.Add(($dates -join ' · ')) }
            if ($ticket.description) { $lines.Add(''); $lines.Add("Description: $($ticket.description)") }
            if ($ticket.resolution)  { $lines.Add(''); $lines.Add("Resolution: $($ticket.resolution)") }

            $body = ($lines -join "`n").Trim()
            $row = [pscustomobject]@{
                tenant_id    = $TenantId
                entity_type  = 'ticket'
                entity_ref   = [string]$ticket.external_id
                title        = $title
                body         = $body
                summary      = $null
                source       = 'autotask'
                metadata     = (@{ account = $ticket.account_name; status = $ticket.status; ticket_number = $ticket.ticket_number } | ConvertTo-Json -Compress)
                content_hash = $null
            }
            $row.content_hash = Get-ImperionContentHash -InputObject @{ title = $row.title; body = $row.body }
            $row
        }

        Write-ImperionLog -Source 'knowledge' -Message 'knowledge tickets composed.' -Data @{ tickets = @($rows).Count }
        return @($rows)
    }
    finally { if ($ownsConnection) { $conn.Dispose() } }
}
