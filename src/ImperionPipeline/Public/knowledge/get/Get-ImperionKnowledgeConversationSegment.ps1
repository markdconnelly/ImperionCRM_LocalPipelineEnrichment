function Get-ImperionKnowledgeConversationSegment {
    <#
    .SYNOPSIS
        Compose a gold knowledge-object row for every conversation transcript segment.
    .DESCRIPTION
        Get-layer composer for the gold tier (CLAUDE.md §6/§7, ADR-0009) for the
        conversational-intelligence vertical (front-end ADR-0068, issue #200). Voice/meeting
        conversations (ACS calls, Teams meetings, manual uploads) are transcribed and diarized
        upstream by the backend orchestrator (ADR-0042); each diarized turn lands in the silver
        `conversation_segment` table — the EMBEDDING UNIT pinned by ADR-0068 decision 3. This
        composer turns every segment into its own knowledge object so the agent retrieves at
        turn granularity ("who said what, when") and a retrieved vector traces back to its
        exact source turn through the citation view (front-end migration request — see
        docs/database/front-end-schema-handoff.md).

        Each segment's `conversation` parent is joined for context (source channel, the linked
        account, and the conversation start time) so the embedded body carries enough framing
        to be useful on its own, while `entity_ref` = the segment id keeps every object 1:1
        with the row the citation view points back to. The composed `body` (speaker + turn
        text + light context) is what gets chunked and embedded (Voyage @1024, ADR-0041);
        `metadata` carries the parent conversation id + account so the backend/citation view
        can resolve the source without re-reading bronze.

        Thin adapter over the knowledge-composer spine Invoke-ImperionKnowledgeCompose
        (#106): this declares the SQL + compose block; the spine owns the scaffold
        (tenant default, connection lifecycle, knowledge_object row emit, content_hash over
        title+body — the idempotency key Set-ImperionKnowledgeObject and the vectorizer both
        honour, so an unchanged segment never re-composes and never re-embeds, §7). Read-only;
        pass -Connection to reuse one DB connection across the knowledge sync.

        PII NOTE: transcript text is sensitive, client-identifying conversation content. It
        flows silver -> gold -> Voyage exactly like ticket descriptions and social messages
        already do; the egress is the pinned-provider embedding path governed by ADR-0041 (a
        tenant for whom Voyage egress is unacceptable swaps to the on-prem model behind the
        same interface). Purged conversations (status='purged') and segment-less or
        retention-expired conversations are excluded so purged turns never reach gold.
    .PARAMETER Connection
        Optional open Npgsql connection. When omitted, one is opened from config and
        disposed before returning.
    .PARAMETER TenantId
        Owning tenant stamp. Defaults to the partner tenant.
    .OUTPUTS
        Flat knowledge_object rows ready for Set-ImperionKnowledgeObject.
    .EXAMPLE
        Get-ImperionKnowledgeConversationSegment | Set-ImperionKnowledgeObject
    .EXAMPLE
        Invoke-ImperionKnowledgeSync -EntityType conversation -Vectorize
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        $Connection,
        [string] $TenantId
    )

    Invoke-ImperionKnowledgeCompose -EntityType 'conversation_segment' -Connection $Connection -TenantId $TenantId `
        -LogLabel 'conversation segments' -CountName 'conversation segments' `
        -EmptyMessage 'knowledge conversation: no transcript segments in silver.' `
        -Query @'
SELECT s.id::text          AS id,
       s.conversation_id::text AS conversation_id,
       s.speaker,
       s.start_ms,
       s.end_ms,
       s.text,
       c.source::text      AS source,
       c.external_ref      AS external_ref,
       c.started_at        AS conversation_started_at,
       a.name              AS account_name
  FROM conversation_segment s
  JOIN conversation c ON c.id = s.conversation_id
  LEFT JOIN account a ON a.id = c.account_id
 WHERE c.status <> 'purged'
   AND s.text IS NOT NULL
   AND length(btrim(s.text)) > 0
 ORDER BY s.conversation_id, s.start_ms NULLS LAST, s.id
'@ -Compose {
        param($segment)

        $channel = switch ($segment.source) {
            'acs'    { 'Call' }
            'teams'  { 'Teams meeting' }
            'upload' { 'Recording' }
            default  { 'Conversation' }
        }
        $speaker = if ($segment.speaker) { $segment.speaker } else { 'Speaker' }

        # Title: a short, human-readable handle for the turn (channel + speaker + snippet).
        $snippet = ($segment.text -replace '\s+', ' ').Trim()
        if ($snippet.Length -gt 80) { $snippet = $snippet.Substring(0, 77).TrimEnd() + '...' }
        $titlePrefix = if ($segment.account_name) { "$channel ($($segment.account_name))" } else { $channel }
        $title = "${titlePrefix} — ${speaker}: $snippet"

        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add("$channel transcript segment")
        if ($segment.account_name) { $lines.Add("Account: $($segment.account_name)") }
        if ($segment.conversation_started_at) { $lines.Add("Conversation started: $($segment.conversation_started_at)") }
        $offset = @(
            if ($null -ne $segment.start_ms) { "start: $($segment.start_ms)ms" }
            if ($null -ne $segment.end_ms)   { "end: $($segment.end_ms)ms" }
        )
        if ($offset) { $lines.Add(($offset -join ' · ')) }
        $lines.Add('')
        $lines.Add("${speaker}: $($segment.text)")

        [pscustomobject]@{
            entity_ref = [string]$segment.id
            title      = $title
            body       = ($lines -join "`n").Trim()
            source     = $segment.source
            metadata   = @{
                conversation_id = $segment.conversation_id
                source          = $segment.source
                speaker         = $segment.speaker
                account         = $segment.account_name
                start_ms        = $segment.start_ms
                end_ms          = $segment.end_ms
            }
        }
    }
}
