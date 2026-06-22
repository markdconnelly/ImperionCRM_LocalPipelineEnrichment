function Invoke-ImperionMyItProcessRecommendationSync {
    <#
    .SYNOPSIS
        Pull myITprocess recommendations into the myitprocess_recommendations bronze table (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/myitprocess/recommendations.task.ps1. Strategic roadmap / QBR / assessment
        recommendations. Credential: SecretStore 'myitprocess-api-key' mirror, else Key Vault
        'myITprocess-API-Key' via the cert SP (an MSP-WIDE vendor credential, ADR-0018); auth is the
        api_token header. Idempotent upsert. Requires Initialize-ImperionContext; fails closed — an
        unreachable key or a missing myitprocess_recommendations table is logged (warn) and skipped,
        never crashing the schedule (issue #195).
    .EXAMPLE
        Invoke-ImperionMyItProcessRecommendationSync
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    try {
        Get-ImperionMyItProcessRecommendation | Set-ImperionMyItProcessRecommendationToBronze
    }
    catch {
        # Credential / schema gate: an unreachable myitprocess-api-key / myITprocess-API-Key, or a
        # missing myitprocess_recommendations table, must not crash the schedule - log loudly and exit;
        # the next run converges (idempotent upsert).
        Write-ImperionLog -Level Warn -Source 'myitprocess' -Message "myITprocess recommendation sync skipped: $($_.Exception.Message)"
    }
}
