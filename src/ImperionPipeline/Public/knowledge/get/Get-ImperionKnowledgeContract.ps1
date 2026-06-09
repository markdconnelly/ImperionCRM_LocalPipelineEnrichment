function Get-ImperionKnowledgeContract {
    <#
    .SYNOPSIS
        Compose gold knowledge-object rows for every Autotask contract in bronze.
    .DESCRIPTION
        Get-layer composer for the gold tier (CLAUDE.md §6/§7, ADR-0009). Contracts get
        their own knowledge objects — beyond the one-line mention in the account body —
        so the agent can retrieve a specific contract's terms (type, dates, costs, SLA)
        with per-entity granularity. Reads the `autotask_contracts` bronze joined through
        the `autotask_companies` link to the owning silver account.

        Output rows are flat PSCustomObjects in the knowledge_object shape
        (entity_type='contract', entity_ref = the Autotask contract id). Read-only;
        pass -Connection to reuse one DB connection across the knowledge sync.
    .PARAMETER Connection
        Optional open Npgsql connection. When omitted, one is opened from config and
        disposed before returning.
    .PARAMETER TenantId
        Owning tenant stamp. Defaults to the partner tenant.
    .OUTPUTS
        Flat knowledge_object rows ready for Set-ImperionKnowledgeObject.
    .EXAMPLE
        Get-ImperionKnowledgeContract | Set-ImperionKnowledgeObject
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
        $contracts = Invoke-ImperionDbQuery -Connection $conn -Sql @'
SELECT c.external_id, c.contract_name, c.contract_number, c.contract_type, c.contract_category,
       c.status, c.start_date, c.end_date, c.estimated_revenue, c.estimated_hours,
       c.service_level_agreement_id, c.description, a.name AS account_name
  FROM autotask_contracts c
  LEFT JOIN autotask_companies ac ON ac.external_ref = c.company_id
  LEFT JOIN account a ON a.id = ac.account_id
 ORDER BY c.contract_name
'@
        if (-not $contracts) {
            Write-ImperionLog -Source 'knowledge' -Message 'knowledge contracts: no autotask_contracts bronze found.'
            return @()
        }

        $rows = foreach ($contract in $contracts) {
            $title = if ($contract.contract_name) { $contract.contract_name } else { "Contract $($contract.external_id)" }
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add("Contract: $title")
            if ($contract.account_name) { $lines.Add("Account: $($contract.account_name)") }
            $facts = @(
                if ($contract.contract_number) { "number: $($contract.contract_number)" }
                if ($contract.contract_type)   { "type: $($contract.contract_type)" }
                if ($contract.contract_category) { "category: $($contract.contract_category)" }
                if ($contract.status)          { "status: $($contract.status)" }
            )
            if ($facts) { $lines.Add(($facts -join ' · ')) }
            $span = @($contract.start_date, $contract.end_date) | Where-Object { $_ }
            if ($span) { $lines.Add("Term: $($span -join ' → ')") }
            $value = @(
                if ($contract.estimated_revenue) { "estimated revenue: $($contract.estimated_revenue)" }
                if ($contract.estimated_hours)   { "estimated hours: $($contract.estimated_hours)" }
                if ($contract.service_level_agreement_id) { "SLA id: $($contract.service_level_agreement_id)" }
            )
            if ($value) { $lines.Add(($value -join ' · ')) }
            if ($contract.description) { $lines.Add(''); $lines.Add("Description: $($contract.description)") }

            $body = ($lines -join "`n").Trim()
            $row = [pscustomobject]@{
                tenant_id    = $TenantId
                entity_type  = 'contract'
                entity_ref   = [string]$contract.external_id
                title        = $title
                body         = $body
                summary      = $null
                source       = 'autotask'
                metadata     = (@{ account = $contract.account_name; status = $contract.status } | ConvertTo-Json -Compress)
                content_hash = $null
            }
            $row.content_hash = Get-ImperionContentHash -InputObject @{ title = $row.title; body = $row.body }
            $row
        }

        Write-ImperionLog -Source 'knowledge' -Message 'knowledge contracts composed.' -Data @{ contracts = @($rows).Count }
        return @($rows)
    }
    finally { if ($ownsConnection) { $conn.Dispose() } }
}
