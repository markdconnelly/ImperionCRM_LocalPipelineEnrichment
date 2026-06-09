function Get-ImperionKnowledgeContact {
    <#
    .SYNOPSIS
        Compose gold knowledge-object rows for every silver contact.
    .DESCRIPTION
        Get-layer composer for the gold tier (CLAUDE.md §6/§7, ADR-0009). Reads the silver
        `contact` records (with their account name) and composes one human-readable text
        body per contact — name, role, profile facts, reachability, and CRM standing — the
        text the agent grounds outreach drafts in.

        Output rows are flat PSCustomObjects in the knowledge_object shape (see
        Get-ImperionKnowledgeAccount). Read-only; pass -Connection to reuse one DB
        connection across the knowledge sync.
    .PARAMETER Connection
        Optional open Npgsql connection. When omitted, one is opened from config and
        disposed before returning.
    .PARAMETER TenantId
        Owning tenant stamp. Defaults to the partner tenant (Imperion's own CRM data).
    .OUTPUTS
        Flat knowledge_object rows ready for Set-ImperionKnowledgeObject.
    .EXAMPLE
        Get-ImperionKnowledgeContact | Set-ImperionKnowledgeObject
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
        $contacts = Invoke-ImperionDbQuery -Connection $conn -Sql @'
SELECT c.id::text AS id, c.full_name, c.title, c.headline, c.location, c.email, c.phone,
       c.crm_stage::text AS crm_stage, c.lifecycle_status, a.name AS account_name
  FROM contact c
  LEFT JOIN account a ON a.id = c.account_id
 ORDER BY c.full_name
'@
        if (-not $contacts) {
            Write-ImperionLog -Source 'knowledge' -Message 'knowledge contacts: no silver contacts found.'
            return @()
        }

        $rows = foreach ($contact in $contacts) {
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add("Contact: $($contact.full_name)")
            if ($contact.title -or $contact.account_name) {
                $role = @($contact.title, $(if ($contact.account_name) { "at $($contact.account_name)" })) | Where-Object { $_ }
                $lines.Add(($role -join ' '))
            }
            if ($contact.headline) { $lines.Add("Headline: $($contact.headline)") }
            if ($contact.location) { $lines.Add("Location: $($contact.location)") }
            $reach = @(
                if ($contact.email) { "email: $($contact.email)" }
                if ($contact.phone) { "phone: $($contact.phone)" }
            )
            if ($reach) { $lines.Add(($reach -join ' · ')) }
            $standing = @(
                if ($contact.crm_stage)        { "CRM stage: $($contact.crm_stage)" }
                if ($contact.lifecycle_status) { "lifecycle: $($contact.lifecycle_status)" }
            )
            if ($standing) { $lines.Add(($standing -join ' · ')) }

            $body = ($lines -join "`n").Trim()
            $row = [pscustomobject]@{
                tenant_id    = $TenantId
                entity_type  = 'contact'
                entity_ref   = $contact.id
                title        = $contact.full_name
                body         = $body
                summary      = $null
                source       = 'local-pipeline'
                metadata     = (@{ account = $contact.account_name } | ConvertTo-Json -Compress)
                content_hash = $null
            }
            $row.content_hash = Get-ImperionContentHash -InputObject @{ title = $row.title; body = $row.body }
            $row
        }

        Write-ImperionLog -Source 'knowledge' -Message 'knowledge contacts composed.' -Data @{ contacts = @($rows).Count }
        return @($rows)
    }
    finally { if ($ownsConnection) { $conn.Dispose() } }
}
