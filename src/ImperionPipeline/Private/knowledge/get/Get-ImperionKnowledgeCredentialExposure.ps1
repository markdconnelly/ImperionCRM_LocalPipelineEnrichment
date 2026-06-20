function Get-ImperionKnowledgeCredentialExposure {
    <#
    .SYNOPSIS
        Compose gold knowledge-object rows for every silver credential exposure.
    .DESCRIPTION
        Get-layer composer for the gold tier (CLAUDE.md §6/§7, ADR-0009). Reads the silver
        `credential_exposure` table (front-end migration 0043 / ADR-0040 — Dark Web ID
        monitoring) joined to its contact/account context, plus a count of the backing
        `darkwebid_exposures` bronze records for provenance.

        PII GUARDRAIL: the body summarizes exposure FACTS only — the compromised login,
        source breach, date, what data classes were exposed, the password *status*
        (plaintext|hashed|none) and the remediation status. No raw `payload_bronze` is
        ever read and no plaintext password ever reaches gold (the silver table holds
        none; the raw Dark Web ID payload stays in bronze).

        Thin adapter over the knowledge-composer spine Invoke-ImperionKnowledgeCompose
        (#106): this declares the SQL + compose block; the spine owns the scaffold.
        Output rows are flat PSCustomObjects in the knowledge_object shape
        (entity_type='exposure', entity_ref = the credential_exposure id). Read-only;
        pass -Connection to reuse one DB connection across the knowledge sync.
    .PARAMETER Connection
        Optional open Npgsql connection. When omitted, one is opened from config and
        disposed before returning.
    .PARAMETER TenantId
        Owning tenant stamp. Defaults to the partner tenant.
    .OUTPUTS
        Flat knowledge_object rows ready for Set-ImperionKnowledgeObject.
    .EXAMPLE
        Get-ImperionKnowledgeCredentialExposure | Set-ImperionKnowledgeObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        $Connection,
        [string] $TenantId
    )

    # Facts only — never select payload_bronze (raw breach payloads can carry
    # plaintext passwords; those stay in bronze, out of the embedded gold text).
    Invoke-ImperionKnowledgeCompose -EntityType 'exposure' -Connection $Connection -TenantId $TenantId `
        -EmptyMessage 'knowledge exposures: no credential_exposure silver found.' `
        -Query @'
SELECT ce.id::text AS id, ce.email, ce.breach_source, ce.breach_date::text AS breach_date,
       array_to_string(ce.exposed_data, ', ') AS exposed_data, ce.password_status,
       ce.severity, ce.status, ce.first_seen_at::text AS first_seen_at,
       ce.last_seen_at::text AS last_seen_at,
       c.full_name AS contact_name, a.name AS account_name,
       (SELECT count(*) FROM darkwebid_exposures dw WHERE dw.exposure_id = ce.id) AS bronze_records
  FROM credential_exposure ce
  LEFT JOIN contact c ON c.id = ce.contact_id
  LEFT JOIN account a ON a.id = ce.account_id
 ORDER BY ce.last_seen_at DESC
'@ -Compose {
        param($exposure)
        $title = "Credential exposure: $($exposure.email)$(if ($exposure.breach_source) { " — $($exposure.breach_source)" })"
        $domain = if ($exposure.email -and $exposure.email -match '@(.+)$') { $Matches[1] } else { $null }
        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add($title)
        $who = @(
            if ($exposure.contact_name) { "contact: $($exposure.contact_name)" }
            if ($exposure.account_name) { "account: $($exposure.account_name)" }
            if ($domain)                { "domain: $domain" }
        )
        if ($who) { $lines.Add(($who -join ' · ')) }
        $facts = @(
            if ($exposure.breach_source) { "source breach: $($exposure.breach_source)" }
            if ($exposure.breach_date)   { "breach date: $($exposure.breach_date)" }
            if ($exposure.severity)      { "severity: $($exposure.severity)" }
            if ($exposure.status)        { "status: $($exposure.status)" }
        )
        if ($facts) { $lines.Add(($facts -join ' · ')) }
        if ($exposure.exposed_data)    { $lines.Add("Exposed data classes: $($exposure.exposed_data)") }
        if ($exposure.password_status) { $lines.Add("Password status: $($exposure.password_status) (the credential itself stays in bronze, never in gold)") }
        $seen = @(
            if ($exposure.first_seen_at) { "first seen: $($exposure.first_seen_at)" }
            if ($exposure.last_seen_at)  { "last seen: $($exposure.last_seen_at)" }
        )
        if ($seen) { $lines.Add(($seen -join ' · ')) }

        [pscustomobject]@{
            entity_ref = [string]$exposure.id
            title      = $title
            body       = ($lines -join "`n").Trim()
            source     = 'darkwebid'
            metadata   = @{
                account = $exposure.account_name; status = $exposure.status
                severity = $exposure.severity; bronze_records = $exposure.bronze_records
            }
        }
    }
}
