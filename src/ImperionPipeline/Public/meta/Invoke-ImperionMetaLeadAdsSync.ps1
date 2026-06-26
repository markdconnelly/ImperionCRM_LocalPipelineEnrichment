function Invoke-ImperionMetaLeadAdsSync {
    <#
    .SYNOPSIS
        Collect Meta Lead Ad forms + their submitted leads into bronze, then run the Lead Ads silver merge.
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) for
        the Meta Lead Ads source (LP #362, transferred from backend #424; App Review use case
        "capture & manage ad leads" / permission leads_retrieval). Hops to the Page token once
        (New Pages Experience, #133) and passes it to the form + lead gets, writes both bronze
        tables, then runs Invoke-ImperionMetaLeadAdsMerge (merge co-locates with ingestion,
        ADR-0026). GATED: until IMPERION_META_PAGE_ID + the page token (carrying
        leads_retrieval) are provisioned (and migration 0207 applied) the task logs the gap
        and exits cleanly — the next run converges (idempotent upsert + NOT-EXISTS merge).
        Lead field_data is PII-adjacent — never logged. Requires Initialize-ImperionContext.
    .EXAMPLE
        Invoke-ImperionMetaLeadAdsSync
    #>
    [CmdletBinding()]
    param()

    $pageId = $env:IMPERION_META_PAGE_ID
    if (-not $pageId) {
        Write-ImperionLog -Level Warn -Source 'meta_lead_ad' -Message 'meta lead ads sync skipped: set IMPERION_META_PAGE_ID (discover with Get-ImperionMetaPageToken -Discover).'
        return
    }

    try {
        # New Pages Experience rejects the system-user token for page-scoped reads (#133):
        # hop to the PAGE token once (must carry leads_retrieval) and pass it to every get.
        # Held in memory only, never logged.
        $pageToken = Get-ImperionMetaPageToken -PageId $pageId

        $forms = @(Get-ImperionMetaLeadForm -PageId $pageId -Token $pageToken)
        $forms | Set-ImperionMetaLeadFormToBronze

        $forms | Get-ImperionMetaLead -PageId $pageId -Token $pageToken | Set-ImperionMetaLeadToBronze

        Invoke-ImperionMetaLeadAdsMerge
    }
    catch {
        # Credential/migration gate: an unreachable page token (or one lacking
        # leads_retrieval) or a not-yet-applied 0207 must not crash the schedule — log
        # loudly and exit; the next run converges. The message never includes lead PII.
        Write-ImperionLog -Level Warn -Source 'meta_lead_ad' -Message "meta lead ads sync skipped (page token w/ leads_retrieval? 0207 applied?): $($_.Exception.Message)"
    }
}
