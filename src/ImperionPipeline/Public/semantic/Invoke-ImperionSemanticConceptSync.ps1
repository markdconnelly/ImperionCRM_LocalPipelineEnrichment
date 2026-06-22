function Invoke-ImperionSemanticConceptSync {
    <#
    .SYNOPSIS
        Compose the OKF semantic-layer bundle into gold `semantic_concept` knowledge objects and
        (optionally) embed them.
    .DESCRIPTION
        The scheduled-task entry point for issue #176 (front-end ADR-0086 bundle / ADR-0041 vector
        contract). It:
          1. Resolves a LOCAL, read-only copy of the front-end OKF bundle (Resolve-ImperionOkfBundle —
             pass -BundlePath for an existing checkout, or let it shallow-clone the front-end repo).
          2. Composes one gold knowledge_object per concept file (Get-ImperionKnowledgeSemanticConcept)
             and upserts them change-detected into `knowledge_object` (Set-ImperionKnowledgeObject).
          3. With -Vectorize, runs the normal chunk→Voyage→pgvector stage scoped to
             entity_type='semantic_concept' so the backend agent can retrieve curated silver-entity
             meaning as RAG grounding.

        DORMANT-friendly: a cold node with no reachable bundle does a clean, fail-closed no-op
        (logs a Warn, returns a zero tally) and never opens the DB. Idempotent and resumable:
        unchanged concepts are not rewritten and never re-embedded (§7). The bundle is PII-free by
        the ADR-0086 conformance rules, so only curated docs are embedded — never row-level data.

        One DB connection is shared across compose + vectorize (ADR-0003 short-lived token).
        Requires Initialize-ImperionContext for the DB write. Named Invoke-*Sync (the repo's
        orchestrator convention); the writes are gated by the ShouldProcess on
        Set-ImperionKnowledgeObject and Invoke-ImperionVectorizeKnowledge.
    .PARAMETER BundlePath
        Existing local checkout of the front-end semantic-layer dir (the one containing tables/).
        If omitted, the bundle is shallow-cloned read-only to a temp directory (needs git + read
        access to the repo).
    .PARAMETER Vectorize
        Also embed the composed concepts (Invoke-ImperionVectorizeKnowledge -EntityType
        'semantic_concept').
    .PARAMETER TenantId
        Owning tenant stamp. Defaults to the partner tenant (company-wide canon knowledge).
    .PARAMETER SourceRepo
        Clone URL of the front-end repo when -BundlePath is omitted.
    .OUTPUTS
        The run tally { concepts; upsert; vectorize }.
    .EXAMPLE
        Invoke-ImperionSemanticConceptSync -Vectorize
    .EXAMPLE
        Invoke-ImperionSemanticConceptSync -BundlePath 'C:\Development\GitHub\ImperionCRM\docs\database\semantic-layer' -Vectorize
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Orchestrator (Invoke-*Sync convention, like Invoke-ImperionKnowledgeSync); the DB writes it delegates to Set-ImperionKnowledgeObject + Invoke-ImperionVectorizeKnowledge each own ShouldProcess.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $BundlePath,
        [switch] $Vectorize,
        [string] $TenantId,
        [string] $SourceRepo = 'https://github.com/markdconnelly/ImperionCRM.git'
    )

    $started = Get-Date
    $resolved = Resolve-ImperionOkfBundle -BundlePath $BundlePath -SourceRepo $SourceRepo

    try {
        if ($resolved.Reason -eq 'clone-failed') {
            Write-ImperionLog -Level Warn -Source 'semantic' -Message 'Semantic-concept sync skipped: could not clone the front-end bundle (no access / git unavailable). Fail-closed no-op.'
            return [pscustomobject]@{ concepts = 0; upsert = $null; vectorize = $null }
        }
        if ($resolved.Reason -eq 'no-bundle') {
            Write-ImperionLog -Level Warn -Source 'semantic' -Message "Semantic-concept sync skipped: no OKF bundle at '$($resolved.BundlePath)'."
            return [pscustomobject]@{ concepts = 0; upsert = $null; vectorize = $null }
        }

        $conn = New-ImperionDbConnection
        try {
            $conceptRows = @(Get-ImperionKnowledgeSemanticConcept -BundlePath $resolved.BundlePath -TenantId $TenantId)
            $tally = [ordered]@{ concepts = $conceptRows.Count; upsert = $null; vectorize = $null }
            $tally['upsert'] = $conceptRows | Set-ImperionKnowledgeObject -Connection $conn

            if ($Vectorize) {
                $tally['vectorize'] = Invoke-ImperionVectorizeKnowledge -Connection $conn -EntityType 'semantic_concept' -TenantId $TenantId
            }
            return [pscustomobject]$tally
        }
        finally { $conn.Dispose() }
    }
    finally {
        if ($resolved.Cleanup -and (Test-Path $resolved.Cleanup)) {
            Remove-Item -Recurse -Force $resolved.Cleanup -ErrorAction SilentlyContinue
        }
        Write-ImperionLog -Level Metric -Source 'semantic' -Message 'Semantic-concept sync complete.' -Data @{ seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 1); vectorize = [bool]$Vectorize }
    }
}
