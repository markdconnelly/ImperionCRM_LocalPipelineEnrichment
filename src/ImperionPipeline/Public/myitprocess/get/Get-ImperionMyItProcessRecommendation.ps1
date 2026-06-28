function Get-ImperionMyItProcessRecommendation {
    <#
    .SYNOPSIS
        Collect myITprocess strategic roadmap/QBR/assessment recommendations → bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for myITprocess (issue #195, ADR-0018) — the vCIO
        advisory layer: strategic roadmap / QBR / assessment recommendations scoped to an ACCOUNT
        (not a device). These feed account health and the QBR narrative. Pure strategic/account
        data: it flattens STRAIGHT to Postgres bronze and SKIPS the IT Glue hub (ADR-0006 §2, the
        CRM/advisory exception — the borderline case called out in ADR-0018 §1). Returns rows;
        does not write. Requires Initialize-ImperionContext.

        AUTH: myITprocess is an MSP-WIDE vendor credential resolved from Key Vault
        (`conn-company-myitprocess`, JSON blob → `apiKey` field) by Resolve-ImperionMyItProcessApiKey
        and sent as the `mitp-api-key` header (URLs are NOT secret-bearing). GATED: until the key
        is provisioned (Mark-gated), the resolver throws and the scheduled task logs the gap and
        exits cleanly.

        TARGET: bronze `myitprocess_recommendations` (front-end-owned schema, migration 0119
        SHIPPED + prod-applied, front-end #674). external_id = the recommendation id (stable) →
        idempotent upsert. NEVER creates the table; fails loudly if absent (ADR-0005). The
        account→client tenant mapping is downstream silver (front-end); this bronze stamps the
        partner tenant and preserves the raw account ref.

        FIELD MAP: the base host/header/wrapper are verified live (issue #297); the per-column
        SOURCE field names below are still modeled from the docs — each keeps a fallback chain so
        a miss lands NULL and raw_payload stays lossless (the KQM/EasyDMARC precedent). Re-verify
        the chain heads against a real `items[]` row on the first successful prod pull (#297).
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant (the recommendation's
        client account is preserved as account_ref; live tenant mapping is downstream silver).
    .PARAMETER BaseUri
        myITprocess Reporting API base. Default 'https://reporting.live.myitprocess.com/public-api/v1'
        (verified live, #297).
    .PARAMETER ApiKey
        myITprocess API key override. Defaults to the Key Vault credential-registry resolution.
    .EXAMPLE
        Get-ImperionMyItProcessRecommendation | Set-ImperionMyItProcessRecommendationToBronze
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId,
        [string] $BaseUri = 'https://reporting.live.myitprocess.com/public-api/v1',
        [string] $ApiKey
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.LocalTenantId }
    $ApiKey = Resolve-ImperionMyItProcessApiKey -ApiKey $ApiKey

    $uri = '{0}/recommendations' -f $BaseUri.TrimEnd('/')
    $recommendations = Invoke-ImperionMyItProcessRequest -ApiKey $ApiKey -Uri $uri

    # First non-null of a chain of plausible source names (StrictMode-safe via Get-ImperionMember).
    $firstOf = {
        param($record, [string[]] $candidates)
        foreach ($candidate in $candidates) {
            $value = Get-ImperionPropertyPath -InputObject $record -Path $candidate
            if ($null -ne $value -and "$value" -ne '') { return $value }
        }
    }

    # The VERIFIED live key (prod recommendations payload, #303) leads each chain; the old
    # doc-modeled guesses stay as fallbacks. Column set mirrors front-end migration 0119
    # (myitprocess_recommendations). Live shape: { id, name, type, priority, status,
    # budgetMonth, client{id,name}, initiative{id}, description, hours, ... }.
    #   assessment_name has NO live source — the recommendations endpoint carries only
    #   initiative{id} (no review/assessment name), so it intentionally lands NULL
    #   (raw_payload stays lossless). Add a head here if a named endpoint surfaces one.
    $map = [ordered]@{
        account_ref          = { param($r) & $firstOf $r @('client.id', 'clientId', 'accountId', 'account.id') }
        assessment_name      = { param($r) & $firstOf $r @('assessmentName', 'assessment.name', 'reviewName') }
        recommendation_title = { param($r) & $firstOf $r @('name', 'title', 'recommendationTitle') }
        category             = { param($r) & $firstOf $r @('type', 'category', 'categoryName', 'category.name') }
        priority             = { param($r) & $firstOf $r @('priority', 'priorityName', 'urgency') }
        status               = { param($r) & $firstOf $r @('status', 'statusName', 'state') }
        target_date          = { param($r) & $firstOf $r @('budgetMonth', 'targetDate', 'dueDate', 'plannedDate') }
    }

    $recommendations | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'myitprocess' -TenantId $TenantId -ExternalIdProperty 'id'
}
