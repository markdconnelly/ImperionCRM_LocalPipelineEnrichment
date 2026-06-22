function Get-ImperionTelivyReport {
    <#
    .SYNOPSIS
        Collect Telivy assessment reports and flatten them to bronze-shaped [PSCustomObject] rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6): reads the Telivy API key from the SecretStore
        (Telivy-API-Key) and pages the reports endpoint via the connect layer, flattening each to
        the standard flat-table envelope. Target: bronze televy_reports (front-end migration 0043)
        → assessment_artifact (source 'televy'). Returns rows; does not write. Requires
        Initialize-ImperionContext.

        CONFIRM BEFORE LIVE USE: the base URL, path, and report field names (title/accountName/
        dimension/reportUrl/…) are ASSUMPTIONS shared with the cloud Pipeline (ADR-0040) — verify
        against the live Telivy API on the first pull. The bronze source value is 'televy' even
        though the secret/folder spell it 'telivy'.
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant.
    .PARAMETER BaseUri
        Telivy API base. Default 'https://api.telivy.com' (placeholder — confirm).
    .EXAMPLE
        Get-ImperionTelivyReport
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId,
        [string] $BaseUri = 'https://api.telivy.com'
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }

    $apiKey = Resolve-ImperionTelivyApiKey
    $records = Invoke-ImperionTelivyRequest -ApiKey $apiKey -Uri ('{0}/reports?page[size]=100' -f $BaseUri.TrimEnd('/'))

    $map = [ordered]@{
        title        = 'title'
        account_name = 'accountName'
        dimension    = 'dimension'
        report_url   = 'reportUrl'
        status       = 'status'
        score        = 'score'
        created_at   = 'createdAt'
        updated_at   = 'updatedAt'
    }

    $records | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'televy' -TenantId $TenantId -ExternalIdProperty 'id'
}
