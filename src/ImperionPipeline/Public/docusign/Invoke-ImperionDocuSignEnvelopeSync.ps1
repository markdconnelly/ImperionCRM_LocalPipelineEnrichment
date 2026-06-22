function Invoke-ImperionDocuSignEnvelopeSync {
    <#
    .SYNOPSIS
        Pull DocuSign envelopes into the docusign_contracts bronze table (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/docusign/envelopes.task.ps1. Credentials are SecretStore secrets
        (docusign-token / docusign-account-id, CLAUDE.md §2). Incremental window via the inline
        IMPERION_DOCUSIGN_SINCE_DAYS env var (default 7; 0 = full backfill from 2000-01-01). Idempotent
        upsert. Requires Initialize-ImperionContext; fails closed — a missing/expired docusign-token or
        docusign-account-id is logged (warn) and skipped, never crashing the schedule.
    .EXAMPLE
        Invoke-ImperionDocuSignEnvelopeSync
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    # Incremental window; set IMPERION_DOCUSIGN_SINCE_DAYS=0 for a full backfill from 2000-01-01.
    $sinceDays = if ($env:IMPERION_DOCUSIGN_SINCE_DAYS) { [int]$env:IMPERION_DOCUSIGN_SINCE_DAYS } else { 7 }
    $fromDate = if ($sinceDays -le 0) { '2000-01-01' } else { (Get-Date).AddDays(-$sinceDays).ToString('yyyy-MM-dd') }

    try {
        Get-ImperionDocuSignEnvelope -FromDate $fromDate | Set-ImperionDocuSignContractToBronze
    }
    catch {
        # Credential gate: missing/expired docusign-token or docusign-account-id must not
        # crash the schedule - log loudly and exit; the operator re-provisions and the next
        # run converges (idempotent upsert).
        Write-ImperionLog -Level Warn -Source 'docusign' -Message "DocuSign envelope sync skipped: $($_.Exception.Message)"
    }
}
