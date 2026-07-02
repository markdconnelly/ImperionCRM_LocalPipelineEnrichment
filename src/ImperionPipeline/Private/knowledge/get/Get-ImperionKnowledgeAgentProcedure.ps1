function Get-ImperionKnowledgeAgentProcedure {
    <#
    .SYNOPSIS
        Compose a gold `agent_procedure` knowledge object per agent operating procedure.
    .DESCRIPTION
        Get-layer composer for the gold tier (CLAUDE.md §6/§7, ADR-0009) for the **agent
        procedure definitions** (front-end ADR-0144 / epic ImperionCRM #1874; LP issue
        #458, extending #455). The DB is the source of truth for what each agent *does*:
        `procedure_definition` holds one row per (agent_key, procedure_key) — business
        goal, trigger event, archetype, autonomy ceiling — and `procedure_step` holds its
        ordered step ladder. This composer rolls each definition plus its steps into ONE
        knowledge object so the brain recall path can answer "which procedure handles an
        inbound DM?" or "what are Belle's triage steps?" from gold.

        `entity_ref = '<agent_key>:<procedure_key>'` (the natural key both tables share);
        the composed `body` is the definition framing (goal · trigger · archetype) plus an
        ordered steps summary (step name, actor, description) — what gets chunked and
        embedded (Voyage @1024, ADR-0041). `metadata` carries `agent_key` / `procedure_key`
        / `archetype` / `status` / `ceiling_level` so recall can filter one agent's
        procedures (`metadata @>` containment) without re-reading the source tables.
        Draft, active, AND retired definitions all compose — status is a metadata facet,
        not a filter (a retired procedure is still recallable history).

        Thin adapter over the knowledge-composer spine Invoke-ImperionKnowledgeCompose
        (#106): this declares the definition SQL, the steps -RelatedQueries lookup (keyed
        on the synthesized `agent_key:procedure_key` ref), and the compose block; the spine
        owns the scaffold (tenant default, connection lifecycle, knowledge_object row emit,
        content_hash over title+body — the idempotency key Set-ImperionKnowledgeObject and
        the vectorizer both honour, so an unchanged procedure never re-composes and never
        re-embeds, §7 — the #458 re-embed-on-change acceptance). Read-only; pass
        -Connection to reuse one DB connection across the knowledge sync.

        PII NOTE: procedure definitions are governance config about the agents themselves —
        PII-free by the ADR-0144 conformance rules. The one people-adjacent column,
        `updated_by` (an operator UPN), is deliberately NOT selected on either table — it
        never reaches body or metadata.
    .PARAMETER Connection
        Optional open Npgsql connection. When omitted, one is opened from config and
        disposed before returning.
    .PARAMETER TenantId
        Owning tenant stamp. Defaults to the partner tenant (agent governance is internal
        company config, not client-tenant data).
    .OUTPUTS
        Flat knowledge_object rows ready for Set-ImperionKnowledgeObject.
    .EXAMPLE
        Get-ImperionKnowledgeAgentProcedure | Set-ImperionKnowledgeObject
    .EXAMPLE
        Invoke-ImperionKnowledgeSync -EntityType agent_procedure -Vectorize
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        $Connection,
        [string] $TenantId
    )

    $relatedQueries = @{
        steps = @{ KeyColumn = 'procedure_ref'; Sql = @'
SELECT s.agent_key || ':' || s.procedure_key AS procedure_ref,
       s.step_key,
       s.name,
       s.description,
       s.actor,
       s.ordinal
  FROM procedure_step s
 ORDER BY s.agent_key, s.procedure_key, s.ordinal NULLS LAST, s.step_key
'@ }
    }

    Invoke-ImperionKnowledgeCompose -EntityType 'agent_procedure' -Connection $Connection -TenantId $TenantId `
        -LogLabel 'agent procedures' -CountName 'agent procedures' `
        -EmptyMessage 'knowledge agent procedures: no procedure_definition rows.' `
        -RelatedQueries $relatedQueries `
        -Query @'
SELECT p.agent_key,
       p.procedure_key,
       p.agent_key || ':' || p.procedure_key AS procedure_ref,
       p.name,
       p.business_goal,
       p.trigger_event,
       p.archetype,
       p.status,
       p.ceiling_level
  FROM procedure_definition p
 ORDER BY p.agent_key, p.procedure_key
'@ -Compose {
        param($procedure, $related)

        $procedureSteps = if ($related['steps'].ContainsKey($procedure.procedure_ref)) { $related['steps'][$procedure.procedure_ref] } else { @() }

        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add('Agent operating procedure')
        $facts = @(
            "agent: $($procedure.agent_key)"
            if ($procedure.archetype) { "archetype: $($procedure.archetype)" }
            if ($procedure.status)    { "status: $($procedure.status)" }
        )
        $lines.Add(($facts -join ' · '))
        if ($procedure.business_goal -or $procedure.trigger_event) { $lines.Add('') }
        if ($procedure.business_goal) { $lines.Add("Goal: $($procedure.business_goal)") }
        if ($procedure.trigger_event) { $lines.Add("Trigger: $($procedure.trigger_event)") }

        if (@($procedureSteps).Count -gt 0) {
            $lines.Add('')
            $lines.Add("Steps ($(@($procedureSteps).Count)):")
            $stepNumber = 0
            foreach ($step in $procedureSteps) {
                $stepNumber++
                $actorLabel = if ($step.actor) { " (actor: $($step.actor))" } else { '' }
                $descriptionSuffix = if ($step.description) { " — $($step.description)" } else { '' }
                $lines.Add("$stepNumber. $($step.name)$actorLabel$descriptionSuffix")
            }
        }

        [pscustomobject]@{
            entity_ref = [string]$procedure.procedure_ref
            title      = $procedure.name
            body       = ($lines -join "`n").Trim()
            source     = 'procedure_definition'
            metadata   = @{
                agent_key     = $procedure.agent_key
                procedure_key = $procedure.procedure_key
                archetype     = $procedure.archetype
                status        = $procedure.status
                ceiling_level = if ($null -ne $procedure.ceiling_level) { [int]$procedure.ceiling_level } else { $null }
                step_count    = @($procedureSteps).Count
            }
        }
    }
}
