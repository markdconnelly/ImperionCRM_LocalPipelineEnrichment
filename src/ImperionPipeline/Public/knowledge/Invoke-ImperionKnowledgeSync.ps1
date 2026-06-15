function Invoke-ImperionKnowledgeSync {
    <#
    .SYNOPSIS
        Build the gold knowledge layer (and optionally its vectors) end to end.
    .DESCRIPTION
        Sync entry point for the gold tier (CLAUDE.md §6/§7, ADR-0009) — the cmdlet the
        scheduled task runs. Composes knowledge objects (accounts, contacts, contracts,
        tickets, devices, credential exposures, assessment artifacts, proposals,
        per-tenant security-posture summaries, FB/IG social interactions, and
        conversation transcript segments) through the
        Get-ImperionKnowledge*
        composers, upserts them change-detected into `knowledge_object`, and — with
        -Vectorize — runs the chunk→Voyage→pgvector stage so the backend agent's
        retrieval surface is current.

        One DB connection is shared across the whole run (ADR-0003 short-lived token).
        Idempotent and resumable: unchanged objects are not rewritten and never re-embedded.
    .PARAMETER EntityType
        'account', 'contact', 'contract', 'ticket', 'device', 'exposure', 'assessment',
        'proposal', 'posture', 'social', 'conversation', or 'all' (default).
    .PARAMETER Vectorize
        Also run Invoke-ImperionVectorizeKnowledge after the gold upsert.
    .PARAMETER TenantId
        Owning tenant stamp for composed rows. Defaults to the partner tenant.
    .OUTPUTS
        Per-entity upsert tallies plus, with -Vectorize, the vectorization tally.
    .EXAMPLE
        Invoke-ImperionKnowledgeSync -Vectorize
    .EXAMPLE
        Invoke-ImperionKnowledgeSync -EntityType account
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [ValidateSet('account', 'contact', 'contract', 'ticket', 'device', 'exposure', 'assessment', 'proposal', 'posture', 'social', 'conversation', 'all')][string] $EntityType = 'all',
        [switch] $Vectorize,
        [string] $TenantId
    )

    $conn = New-ImperionDbConnection
    try {
        $tallies = [ordered]@{}

        if ($EntityType -in 'account', 'all') {
            $accountRows = Get-ImperionKnowledgeAccount -Connection $conn -TenantId $TenantId
            $tallies['account'] = $accountRows | Set-ImperionKnowledgeObject -Connection $conn
        }
        if ($EntityType -in 'contact', 'all') {
            $contactRows = Get-ImperionKnowledgeContact -Connection $conn -TenantId $TenantId
            $tallies['contact'] = $contactRows | Set-ImperionKnowledgeObject -Connection $conn
        }
        if ($EntityType -in 'contract', 'all') {
            $contractRows = Get-ImperionKnowledgeContract -Connection $conn -TenantId $TenantId
            $tallies['contract'] = $contractRows | Set-ImperionKnowledgeObject -Connection $conn
        }
        if ($EntityType -in 'ticket', 'all') {
            $ticketRows = Get-ImperionKnowledgeTicket -Connection $conn -TenantId $TenantId
            $tallies['ticket'] = $ticketRows | Set-ImperionKnowledgeObject -Connection $conn
        }
        if ($EntityType -in 'device', 'all') {
            $deviceRows = Get-ImperionKnowledgeDevice -Connection $conn -TenantId $TenantId
            $tallies['device'] = $deviceRows | Set-ImperionKnowledgeObject -Connection $conn
        }
        if ($EntityType -in 'exposure', 'all') {
            $exposureRows = Get-ImperionKnowledgeCredentialExposure -Connection $conn -TenantId $TenantId
            $tallies['exposure'] = $exposureRows | Set-ImperionKnowledgeObject -Connection $conn
        }
        if ($EntityType -in 'assessment', 'all') {
            $artifactRows = Get-ImperionKnowledgeAssessmentArtifact -Connection $conn -TenantId $TenantId
            $tallies['assessment'] = $artifactRows | Set-ImperionKnowledgeObject -Connection $conn
        }
        if ($EntityType -in 'proposal', 'all') {
            $proposalRows = Get-ImperionKnowledgeProposal -Connection $conn -TenantId $TenantId
            $tallies['proposal'] = $proposalRows | Set-ImperionKnowledgeObject -Connection $conn
        }
        if ($EntityType -in 'posture', 'all') {
            $postureRows = Get-ImperionKnowledgePosture -Connection $conn -TenantId $TenantId
            $tallies['posture'] = $postureRows | Set-ImperionKnowledgeObject -Connection $conn
        }
        if ($EntityType -in 'social', 'all') {
            $socialRows = Get-ImperionKnowledgeSocial -Connection $conn -TenantId $TenantId
            $tallies['social'] = $socialRows | Set-ImperionKnowledgeObject -Connection $conn
        }
        if ($EntityType -in 'conversation', 'all') {
            $conversationRows = Get-ImperionKnowledgeConversationSegment -Connection $conn -TenantId $TenantId
            $tallies['conversation'] = $conversationRows | Set-ImperionKnowledgeObject -Connection $conn
        }

        if ($Vectorize) {
            # The conversation composer stamps entity_type='conversation_segment' (the
            # ADR-0041 embedding unit); the sync's 'conversation' switch maps to it so a
            # scoped -EntityType conversation vectorize run filters the right gold rows.
            $vectorEntityType = switch ($EntityType) {
                'all'          { $null }
                'conversation' { 'conversation_segment' }
                default        { $EntityType }
            }
            $tallies['vectorize'] = Invoke-ImperionVectorizeKnowledge -Connection $conn -EntityType $vectorEntityType -TenantId $TenantId
        }

        return [pscustomobject]$tallies
    }
    finally { $conn.Dispose() }
}
