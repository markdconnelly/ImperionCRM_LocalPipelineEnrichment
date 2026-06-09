function Split-ImperionTextChunk {
    <#
    .SYNOPSIS
        Split a knowledge-object body into chunking-v1 chunks for embedding.
    .DESCRIPTION
        Pure text helper for the vectorization stage (CLAUDE.md §7, ADR-0009). Implements
        chunking version v1: chunks of at most -MaxChars characters with -OverlapChars of
        trailing context carried into the next chunk. Within the final fifth of a chunk
        window the split prefers a paragraph boundary (newline), then a sentence/word
        boundary, so chunks read naturally and retrieval doesn't land mid-word.

        Deterministic and side-effect free — the same body always produces the same chunk
        list, which is what makes content-hash idempotency (no re-embed, no re-bill) work.
    .PARAMETER Text
        The text to chunk (a knowledge_object body).
    .PARAMETER MaxChars
        Maximum characters per chunk. Defaults to the pinned v1 policy (6000).
    .PARAMETER OverlapChars
        Characters of overlap carried from the end of one chunk into the next. Defaults to
        the pinned v1 policy (500).
    .OUTPUTS
        [string[]] — one or more chunks in document order. Empty/whitespace input yields none.
    .EXAMPLE
        $chunks = Split-ImperionTextChunk -Text $knowledgeObject.body
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string] $Text,
        [ValidateRange(200, 100000)][int] $MaxChars = (Get-ImperionVectorContract).MaxChunkChars,
        [ValidateRange(0, 5000)][int] $OverlapChars = (Get-ImperionVectorContract).OverlapChars
    )

    $trimmed = $Text.Trim()
    if ($trimmed.Length -eq 0) { return @() }
    if ($trimmed.Length -le $MaxChars) { return @($trimmed) }

    $chunks = [System.Collections.Generic.List[string]]::new()
    $position = 0
    while ($position -lt $trimmed.Length) {
        $remaining = $trimmed.Length - $position
        if ($remaining -le $MaxChars) {
            $chunks.Add($trimmed.Substring($position).Trim())
            break
        }

        # Prefer a natural boundary inside the final fifth of the window: paragraph, then
        # sentence end, then any whitespace. Fall back to a hard cut at MaxChars.
        $windowEnd = $position + $MaxChars
        $searchFrom = $windowEnd - [int]($MaxChars / 5)
        $cut = $windowEnd
        foreach ($boundaryPattern in "`n", '. ', ' ') {
            $candidate = $trimmed.LastIndexOf($boundaryPattern, $windowEnd - 1, $windowEnd - $searchFrom)
            if ($candidate -gt $position) { $cut = $candidate + $boundaryPattern.Length; break }
        }

        $chunks.Add($trimmed.Substring($position, $cut - $position).Trim())
        # Next chunk starts OverlapChars back from the cut so boundary-spanning context
        # is retrievable from either side.
        $position = [math]::Max($cut - $OverlapChars, $position + 1)
    }

    return $chunks.ToArray()
}
