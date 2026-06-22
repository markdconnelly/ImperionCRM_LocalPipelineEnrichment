function Get-ImperionKnowledgeMemory {
    <#
    .SYNOPSIS
        Compose a gold `memory` knowledge object per deliberate-capture conversation thread.
    .DESCRIPTION
        Get-layer composer for the gold tier (CLAUDE.md §6/§7, ADR-0009) for the **verbatim
        memory tier** of the Universal Memory store (front-end ADR-0113 verbatim / ADR-0115
        gold ranker / ADR-0116 Memory MCP; LP issue #300; epic ImperionCRM #966/#1152).

        The bronze verbatim substrate is `memory_drawer` (front-end migration 0167 + 0170
        `agent_slug`): one short row per deliberate capture — a human note / conversation turn
        or an agent memory written through the Memory MCP `store`. This composer rolls a
        conversation's drawer rows up into ONE gold `knowledge_object` (`entity_type='memory'`,
        `entity_ref = conversation_id`) whose `body` is the ordered transcript. That gold
        summary is what the backend recall path embeds + hybrid-ranks (the FE ADR-0115 ranker,
        mirrored backend-side in `gold-knowledge-ranker.ts`); a hit's `entity_ref` is the
        conversation id the orchestrator DRILLS back to for the verbatim rows (ADR-0113 —
        reason over the summary, recall the verbatim).

        **Rescope note (2026-06-22, ADR-0114 §9).** #300's original sketch embedded an
        *inline* `embedding vector(1024)` column on `memory_drawer`. That column does not exist
        (verified against the live schema) and the design was superseded: recall is
        gold-summary→drill, not an inline per-row vector (no `personal_embedding`/`embed_state`).
        So this is the gold path — `memory_drawer` → gold `memory` `knowledge_object` →
        `knowledge_embedding` via the normal vectorizer — exactly the boundary BE #302 records
        ("LP #300 owns gold: memory_drawer → gold memory summary + embedding").

        The `metadata` facets — `wing`, `room`, `agent_slug` — are the EXACT keys the recall
        path filters on (`recallMemory` builds a `knowledge_object.metadata @>` containment
        filter from wing/room/agent_slug), so scoped recall ("this agent's room") works without
        re-reading bronze. A conversation is single-scope by construction; a stable `max()` per
        facet collapses any stray divergence deterministically.

        Thin adapter over the knowledge-composer spine `Invoke-ImperionKnowledgeCompose` (#106):
        this declares the SQL + compose block; the spine owns the scaffold (tenant default,
        connection lifecycle, knowledge_object row emit, content_hash over title+body — the
        idempotency key `Set-ImperionKnowledgeObject` and the vectorizer both honour, so an
        unchanged thread never re-composes and never re-embeds, §7). Read-only; pass -Connection
        to reuse one DB connection across the knowledge sync.

        PII NOTE: drawer bodies are PII-bearing verbatim memory. They flow
        bronze→gold→Voyage exactly like ticket descriptions, social messages, and conversation
        transcript segments already do; the egress is the pinned-provider embedding path
        governed by ADR-0041 (a context for whom Voyage egress is unacceptable swaps to the
        on-prem model behind the same interface). Verbatim is embedded **in place** — never
        copied off-box. Empty-bodied rows are excluded.
    .PARAMETER Connection
        Optional open Npgsql connection. When omitted, one is opened from config and disposed
        before returning.
    .PARAMETER TenantId
        Owning tenant stamp. Defaults to the partner tenant (memory is internal company memory,
        not client-tenant data).
    .OUTPUTS
        Flat knowledge_object rows ready for Set-ImperionKnowledgeObject.
    .EXAMPLE
        Get-ImperionKnowledgeMemory | Set-ImperionKnowledgeObject
    .EXAMPLE
        Invoke-ImperionKnowledgeSync -EntityType memory -Vectorize
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        $Connection,
        [string] $TenantId
    )

    Invoke-ImperionKnowledgeCompose -EntityType 'memory' -Connection $Connection -TenantId $TenantId `
        -LogLabel 'memory threads' -CountName 'memory threads' `
        -EmptyMessage 'knowledge memory: no deliberate-capture rows in memory_drawer.' `
        -Query @'
SELECT d.conversation_id::text                     AS conversation_id,
       count(*)                                    AS turn_count,
       max(d.created_at)                           AS last_turn_at,
       -- Scope facets — the keys the recall path filters on. A thread is single-scope by
       -- construction; max() is a stable deterministic pick if a stray row diverges.
       max(d.wing)                                 AS wing,
       max(d.room)                                 AS room,
       max(d.agent_slug)                           AS agent_slug,
       max(d.owner_user_id::text)                  AS owner_user_id,
       -- The ordered verbatim transcript = the gold body that gets chunked + embedded.
       string_agg(
         coalesce(nullif(d.role, ''), 'note') || ': ' || d.body,
         E'\n' ORDER BY d.turn_index NULLS LAST, d.created_at
       )                                           AS transcript
  FROM memory_drawer d
 WHERE d.body IS NOT NULL
   AND length(btrim(d.body)) > 0
 GROUP BY d.conversation_id
 ORDER BY d.conversation_id
'@ -Compose {
        param($conversation)

        $turnCount = [int]$conversation.turn_count
        $scopeBits = @(
            if ($conversation.wing)       { "wing: $($conversation.wing)" }
            if ($conversation.room)       { "room: $($conversation.room)" }
            if ($conversation.agent_slug) { "agent: $($conversation.agent_slug)" }
        ) -join ' · '

        $turnLabel = if ($turnCount -eq 1) { '1 turn' } else { "$turnCount turns" }
        $title = if ($scopeBits) { "Memory — ${scopeBits} (${turnLabel})" } else { "Memory thread (${turnLabel})" }

        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add('Deliberate-capture memory thread')
        if ($scopeBits) { $lines.Add($scopeBits) }
        if ($conversation.last_turn_at) { $lines.Add("Last turn: $($conversation.last_turn_at)") }
        $lines.Add('')
        $lines.Add($conversation.transcript)

        [pscustomobject]@{
            entity_ref = [string]$conversation.conversation_id
            title      = $title
            body       = ($lines -join "`n").Trim()
            source     = 'memory_drawer'
            metadata   = @{
                conversation_id = $conversation.conversation_id
                wing            = $conversation.wing
                room            = $conversation.room
                agent_slug      = $conversation.agent_slug
                owner_user_id   = $conversation.owner_user_id
                turn_count      = $turnCount
            }
        }
    }
}
