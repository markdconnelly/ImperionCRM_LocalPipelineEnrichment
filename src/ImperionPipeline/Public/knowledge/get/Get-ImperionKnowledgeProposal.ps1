function Get-ImperionKnowledgeProposal {
    <#
    .SYNOPSIS
        Compose gold knowledge-object rows for every proposal.
    .DESCRIPTION
        Get-layer composer for the gold tier (CLAUDE.md §6/§7, ADR-0009). Reads the silver
        `proposal` table (front-end migration 0008 / ADR-0019 — the lifecycle artifact the
        web app CRUDs today, later augmented by the KQM feed) joined through its owning
        `opportunity` to the account, and composes one body per proposal: title, lifecycle
        status (draft → sent → accepted/declined), quoted monthly value, the opportunity
        and account it belongs to, lifecycle dates, and notes.

        Output rows are flat PSCustomObjects in the knowledge_object shape
        (entity_type='proposal', entity_ref = the proposal id). Read-only;
        pass -Connection to reuse one DB connection across the knowledge sync.
    .PARAMETER Connection
        Optional open Npgsql connection. When omitted, one is opened from config and
        disposed before returning.
    .PARAMETER TenantId
        Owning tenant stamp. Defaults to the partner tenant.
    .OUTPUTS
        Flat knowledge_object rows ready for Set-ImperionKnowledgeObject.
    .EXAMPLE
        Get-ImperionKnowledgeProposal | Set-ImperionKnowledgeObject
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
        $proposals = Invoke-ImperionDbQuery -Connection $conn -Sql @'
SELECT p.id::text AS id, p.title, p.status::text AS status, p.amount_mrr::text AS amount_mrr,
       p.notes, p.sent_at::text AS sent_at, p.decided_at::text AS decided_at,
       p.created_at::text AS created_at,
       o.name AS opportunity_name, o.sales_stage::text AS sales_stage,
       a.name AS account_name
  FROM proposal p
  LEFT JOIN opportunity o ON o.id = p.opportunity_id
  LEFT JOIN account a ON a.id = o.account_id
 ORDER BY p.created_at DESC
'@
        if (-not $proposals) {
            Write-ImperionLog -Source 'knowledge' -Message 'knowledge proposals: no proposal rows found.'
            return @()
        }

        $rows = foreach ($proposal in $proposals) {
            $title = if ($proposal.title) { $proposal.title } else { "Proposal $($proposal.id)" }
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add("Proposal: $title")
            $context = @(
                if ($proposal.account_name)     { "account: $($proposal.account_name)" }
                if ($proposal.opportunity_name) { "opportunity: $($proposal.opportunity_name)" }
                if ($proposal.sales_stage)      { "opportunity stage: $($proposal.sales_stage)" }
            )
            if ($context) { $lines.Add(($context -join ' · ')) }
            $facts = @(
                if ($proposal.status)     { "status: $($proposal.status)" }
                if ($proposal.amount_mrr) { "quoted monthly value: $($proposal.amount_mrr)" }
            )
            if ($facts) { $lines.Add(($facts -join ' · ')) }
            $dates = @(
                if ($proposal.created_at) { "created: $($proposal.created_at)" }
                if ($proposal.sent_at)    { "sent: $($proposal.sent_at)" }
                if ($proposal.decided_at) { "decided: $($proposal.decided_at)" }
            )
            if ($dates) { $lines.Add(($dates -join ' · ')) }
            if ($proposal.notes) { $lines.Add(''); $lines.Add("Notes: $($proposal.notes)") }

            $body = ($lines -join "`n").Trim()
            $row = [pscustomobject]@{
                tenant_id    = $TenantId
                entity_type  = 'proposal'
                entity_ref   = [string]$proposal.id
                title        = $title
                body         = $body
                summary      = $null
                source       = 'local-pipeline'
                metadata     = (@{
                    account = $proposal.account_name; opportunity = $proposal.opportunity_name
                    status = $proposal.status
                } | ConvertTo-Json -Compress)
                content_hash = $null
            }
            $row.content_hash = Get-ImperionContentHash -InputObject @{ title = $row.title; body = $row.body }
            $row
        }

        Write-ImperionLog -Source 'knowledge' -Message 'knowledge proposals composed.' -Data @{ proposals = @($rows).Count }
        return @($rows)
    }
    finally { if ($ownsConnection) { $conn.Dispose() } }
}
