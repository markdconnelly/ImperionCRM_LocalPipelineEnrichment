function Get-ImperionVectorContract {
    <#
    .SYNOPSIS
        The pinned vector contract — model, dimension, chunking policy — read from the ONE
        machine-readable home (ADR-0009; front-end ADR-0102).
    .DESCRIPTION
        The front end owns the single source of truth for the vector contract
        (`ImperionCRM/db/contracts/vector-contract.json`, front-end ADR-0102): Voyage
        `voyage-3-large` at dimension 1024, chunking `v1` (6000 chars / 500 overlap), the
        Voyage API shaping, and the cost rate. This module ships a **vendored copy**
        (`vector-contract.json`, beside this file) and projects it into the flat object the
        rest of the module already consumes — so callers (`Get-ImperionVoyageEmbedding`,
        `Split-ImperionTextChunk`, `Invoke-ImperionVectorizeKnowledge`) are unchanged.

        The values are no longer restated here: every embedding write stamps these and every
        backend query filters on them, so vector spaces can never silently mix. Changing the
        model or chunking policy means editing the front-end home, re-vendoring the copy here,
        and running a VERSIONED re-embed (docs/database/vector-lifecycle.md) — never editing
        in place. CI verifies the vendored copy against the canonical and fails on drift
        (tests/Get-ImperionVectorContract.Tests.ps1).

        Fails loud if the vendored contract file is absent or malformed.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $contractPath = Join-Path $PSScriptRoot 'vector-contract.json'
    if (-not (Test-Path -LiteralPath $contractPath)) {
        throw "Vector contract file not found at '$contractPath'. The vendored copy of the front-end home (ADR-0102) is missing."
    }

    try {
        $contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
    } catch {
        throw "Vector contract at '$contractPath' is not valid JSON: $($_.Exception.Message)"
    }

    # Fail loud on a malformed contract rather than silently embedding into the wrong space.
    foreach ($required in 'embeddingModel', 'dimension', 'chunkingVersion', 'chunking', 'provider') {
        if ($null -eq $contract.$required) {
            throw "Vector contract at '$contractPath' is missing required field '$required'."
        }
    }
    if (($contract.dimension -as [int]) -le 0) {
        throw "Vector contract dimension must be a positive integer; got '$($contract.dimension)'."
    }

    # Project the canonical contract into the flat shape the module already consumes.
    [pscustomobject]@{
        EmbeddingModel  = $contract.embeddingModel
        Dimension       = [int] $contract.dimension
        ChunkingVersion = $contract.chunkingVersion
        # v1 chunking policy: ~1,500 tokens per chunk at the 4-chars/token heuristic,
        # with overlap so context spanning a boundary is retrievable from either side.
        MaxChunkChars   = [int] $contract.chunking.maxChunkChars
        OverlapChars    = [int] $contract.chunking.overlapChars
        # Voyage API request shaping (https://docs.voyageai.com): max inputs per call.
        ApiBatchSize    = [int] $contract.provider.batchSize
        ApiBaseUri      = $contract.provider.baseUri
        # Approximate list price for cost telemetry (USD per million tokens, input-only).
        UsdPerMillionTokens = [double] $contract.provider.usdPerMillionTokens
    }
}
