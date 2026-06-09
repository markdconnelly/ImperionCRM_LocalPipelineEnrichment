function Get-ImperionVectorContract {
    <#
    .SYNOPSIS
        The pinned vector contract — model, dimension, chunking policy — in ONE place (ADR-0009).
    .DESCRIPTION
        Front-end ADR-0041 pins the system-wide embedding contract: Voyage `voyage-3-large`
        at dimension 1024. Every embedding write stamps these values and every backend query
        filters on them, so vector spaces can never silently mix. Chunking `v1` is defined
        here too (size/overlap in characters; chunks prefer paragraph boundaries — see
        Split-ImperionTextChunk). Changing the model or the chunking policy means bumping
        the version and running a VERSIONED re-embed (docs/database/vector-lifecycle.md) —
        never editing these values in place.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    [pscustomobject]@{
        EmbeddingModel  = 'voyage-3-large'
        Dimension       = 1024
        ChunkingVersion = 'v1'
        # v1 chunking policy: ~1,500 tokens per chunk at the 4-chars/token heuristic,
        # with overlap so context spanning a boundary is retrievable from either side.
        MaxChunkChars   = 6000
        OverlapChars    = 500
        # Voyage API request shaping (https://docs.voyageai.com): max inputs per call.
        ApiBatchSize    = 64
        ApiBaseUri      = 'https://api.voyageai.com/v1/embeddings'
        # Approximate list price for cost telemetry (USD per million tokens, input-only).
        UsdPerMillionTokens = 0.18
    }
}
