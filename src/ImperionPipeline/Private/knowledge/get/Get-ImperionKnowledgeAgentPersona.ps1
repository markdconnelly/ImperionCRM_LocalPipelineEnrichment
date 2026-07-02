function Get-ImperionKnowledgeAgentPersona {
    <#
    .SYNOPSIS
        Compose a gold `agent_persona` knowledge object per agent persona section.
    .DESCRIPTION
        Get-layer composer for the gold tier (CLAUDE.md §6/§7, ADR-0009) for the **agent
        persona narrative** (front-end ADR-0144 / epic ImperionCRM #1874; LP issues #455 +
        #458). The DB is the source of truth for who each agent *is*: `agent_persona_section`
        (front-end migration 0263) holds one markdown section per (agent, section_key) —
        the ELEVEN persona keys (identity_mandate, origin_character, motivations_kpis,
        how_you_work, relationships_escalation, voice_tone, example_interactions,
        grounding_uncertainty, behavioral_guardrails, quality_bar, boundaries). This
        composer turns every section row into its own knowledge object so persona narrative
        is pg-retrievable by the brain recall path at section granularity ("how does Belle
        escalate?" retrieves her relationships_escalation section, not a 3000-word blob).

        `entity_ref = '<agent_key>:<section_key>'` keeps each object 1:1 with its source
        row; `metadata` carries `agent_key` / `section_key` / `ordinal` so recall can filter
        to one agent's persona (`metadata @>` containment) without re-reading the source
        table. The composed `body` (light framing + the section markdown) is what gets
        chunked and embedded (Voyage @1024, ADR-0041).

        Thin adapter over the knowledge-composer spine Invoke-ImperionKnowledgeCompose
        (#106): this declares the SQL + compose block; the spine owns the scaffold (tenant
        default, connection lifecycle, knowledge_object row emit, content_hash over
        title+body — the idempotency key Set-ImperionKnowledgeObject and the vectorizer both
        honour, so an unchanged section never re-composes and never re-embeds, §7 — the
        #458 re-embed-on-change acceptance). Read-only; pass -Connection to reuse one DB
        connection across the knowledge sync.

        PII NOTE: persona sections are governance config about the agents themselves —
        PII-free by the ADR-0144 conformance rules (persona narrative, never client or
        row-level data). The one people-adjacent column, `updated_by` (an operator UPN), is
        deliberately NOT selected — it never reaches body or metadata.
    .PARAMETER Connection
        Optional open Npgsql connection. When omitted, one is opened from config and
        disposed before returning.
    .PARAMETER TenantId
        Owning tenant stamp. Defaults to the partner tenant (agent governance is internal
        company config, not client-tenant data).
    .OUTPUTS
        Flat knowledge_object rows ready for Set-ImperionKnowledgeObject.
    .EXAMPLE
        Get-ImperionKnowledgeAgentPersona | Set-ImperionKnowledgeObject
    .EXAMPLE
        Invoke-ImperionKnowledgeSync -EntityType agent_persona -Vectorize
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        $Connection,
        [string] $TenantId
    )

    Invoke-ImperionKnowledgeCompose -EntityType 'agent_persona' -Connection $Connection -TenantId $TenantId `
        -LogLabel 'agent persona sections' -CountName 'agent persona sections' `
        -EmptyMessage 'knowledge agent personas: no agent_persona_section rows.' `
        -Query @'
SELECT s.agent_key,
       s.section_key,
       s.ordinal,
       s.body_md
  FROM agent_persona_section s
 WHERE s.body_md IS NOT NULL
   AND length(btrim(s.body_md)) > 0
 ORDER BY s.agent_key, s.ordinal NULLS LAST, s.section_key
'@ -Compose {
        param($section)

        # Humanize the section key for the title: 'identity_mandate' -> 'Identity mandate'.
        $sectionLabel = [string]($section.section_key -replace '_', ' ')
        if ($sectionLabel.Length -gt 0) {
            $sectionLabel = $sectionLabel.Substring(0, 1).ToUpperInvariant() + $sectionLabel.Substring(1)
        }

        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add('Agent persona section')
        $lines.Add("Agent: $($section.agent_key) · Section: $sectionLabel")
        $lines.Add('')
        $lines.Add([string]$section.body_md)

        [pscustomobject]@{
            entity_ref = "$($section.agent_key):$($section.section_key)"
            title      = "Agent persona — $($section.agent_key): $sectionLabel"
            body       = ($lines -join "`n").Trim()
            source     = 'agent_persona_section'
            metadata   = @{
                agent_key   = $section.agent_key
                section_key = $section.section_key
                ordinal     = if ($null -ne $section.ordinal) { [int]$section.ordinal } else { $null }
            }
        }
    }
}
