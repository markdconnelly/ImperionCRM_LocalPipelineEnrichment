function Get-ImperionKnowledgeAssessmentArtifact {
    <#
    .SYNOPSIS
        Compose gold knowledge-object rows for every assessment artifact.
    .DESCRIPTION
        Get-layer composer for the gold tier (CLAUDE.md §6/§7, ADR-0009). Reads the silver
        `assessment_artifact` evidence store (front-end migration 0013 / ADR-0023 — Telivy
        reports, M365/Google snapshots, scans, phishing sims) joined to its owning
        `assessment` and account, plus a count of the backing `televy_reports` bronze
        records (migration 0043 / ADR-0040) for provenance. The artifact's own
        `summary_gold` — when the merge has produced one — is the body's centerpiece.

        Thin adapter over the knowledge-composer spine Invoke-ImperionKnowledgeCompose
        (#106): this declares the SQL + compose block; the spine owns the scaffold.
        Output rows are flat PSCustomObjects in the knowledge_object shape
        (entity_type='assessment', entity_ref = the assessment_artifact id). Read-only;
        pass -Connection to reuse one DB connection across the knowledge sync.
    .PARAMETER Connection
        Optional open Npgsql connection. When omitted, one is opened from config and
        disposed before returning.
    .PARAMETER TenantId
        Owning tenant stamp. Defaults to the partner tenant.
    .OUTPUTS
        Flat knowledge_object rows ready for Set-ImperionKnowledgeObject.
    .EXAMPLE
        Get-ImperionKnowledgeAssessmentArtifact | Set-ImperionKnowledgeObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        $Connection,
        [string] $TenantId
    )

    Invoke-ImperionKnowledgeCompose -EntityType 'assessment' -Connection $Connection -TenantId $TenantId `
        -LogLabel 'assessment artifacts' -CountName 'artifacts' `
        -EmptyMessage 'knowledge assessment artifacts: no assessment_artifact rows found.' `
        -Query @'
SELECT aa.id::text AS id, aa.source::text AS source, aa.kind::text AS kind, aa.title,
       aa.dimension, aa.collected_at::text AS collected_at, aa.summary_gold, aa.external_ref,
       ass.name AS assessment_name, ass.status::text AS assessment_status,
       a.name AS account_name,
       (SELECT count(*) FROM televy_reports tr WHERE tr.artifact_id = aa.id) AS televy_reports
  FROM assessment_artifact aa
  LEFT JOIN assessment ass ON ass.id = aa.assessment_id
  LEFT JOIN account a ON a.id = ass.account_id
 ORDER BY aa.collected_at DESC
'@ -Compose {
        param($artifact)
        $title = if ($artifact.title) { $artifact.title } else { "$($artifact.source) $($artifact.kind) $($artifact.id)" }
        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add("Assessment artifact: $title")
        $context = @(
            if ($artifact.assessment_name) { "assessment: $($artifact.assessment_name)" }
            if ($artifact.assessment_status) { "assessment status: $($artifact.assessment_status)" }
            if ($artifact.account_name)   { "account: $($artifact.account_name)" }
        )
        if ($context) { $lines.Add(($context -join ' · ')) }
        $facts = @(
            if ($artifact.source)       { "source: $($artifact.source)" }
            if ($artifact.kind)         { "kind: $($artifact.kind)" }
            if ($artifact.dimension)    { "scorecard dimension: $($artifact.dimension)" }
            if ($artifact.collected_at) { "collected: $($artifact.collected_at)" }
        )
        if ($facts) { $lines.Add(($facts -join ' · ')) }
        if ($artifact.summary_gold) { $lines.Add(''); $lines.Add("Summary: $($artifact.summary_gold)") }

        [pscustomobject]@{
            entity_ref = [string]$artifact.id
            title      = $title
            body       = ($lines -join "`n").Trim()
            source     = $artifact.source
            metadata   = @{
                assessment = $artifact.assessment_name; account = $artifact.account_name
                kind = $artifact.kind; televy_reports = $artifact.televy_reports
            }
        }
    }
}
