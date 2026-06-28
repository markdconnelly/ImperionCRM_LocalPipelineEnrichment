function Get-ImperionQboProfitAndLoss {
    <#
    .SYNOPSIS
        Pull a QuickBooks Online Profit & Loss report for a period and flatten it to a single
        immutable bronze snapshot row.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for the QBO **Profit & Loss** REPORT — a period revenue /
        expense / net-income snapshot. Part of the read-only full QBO finance pull into the
        intelligence / BI engine (ADR-0020, issue #197): the period P&L feeding revenue / margin BI.
        Pure finance data: flattens STRAIGHT to Postgres and SKIPS the IT Glue hub (ADR-0006).

        REPORT, NOT ENTITY. Unlike the entity collectors this calls the QBO **Reports** API
        (`GET /v3/company/{realmId}/reports/ProfitAndLoss?start_date&end_date&...`), not the SQL-like
        `/query` endpoint — so it does not use `Invoke-ImperionQboRequest` (which is query-only). It
        reads the same `qbo-access-token` / `qbo-realm-id` secrets and the same retry/transport core
        (`Invoke-ImperionRestWithRetry`). The report comes back as ONE document; this collector lands
        ONE immutable snapshot row per `period` (the snapshot idiom of ADR-0011, not the upsert-on-Id
        entity idiom) — the whole report JSON is preserved in raw_payload and a few headline totals
        are surfaced as flat columns for BI.

        TARGET: bronze `qbo_profit_and_loss` (front-end-owned schema, ADR-0042 — front-end migration
        0120, front-end #688). Idempotent external_id = the `period` (e.g. '2026-06'), so the
        standard `(tenant_id, source, external_id)` upsert + content-hash skip make a re-pull of the
        same period converge (an unchanged snapshot is never rewritten). Deploy-ahead/gated on the
        QBO app registration.

        CONFIRM BEFORE LIVE USE (gated on Mark's QBO app registration): the report path / params, the
        Header + Rows JSON shape (and exactly where Total Income / Total Expenses / Net Income sit in
        it), the production host, and the minor version are modeled from the documented Intuit
        Reports API but UNVERIFIED against the real company. Headline totals lead with the documented
        summary-row labels and keep a fallback chain; an unmatched total lands NULL and nothing is
        lost (the full report in raw_payload).
    .PARAMETER TenantId
        Owning tenant stamped on the snapshot row; defaults to the partner tenant.
    .PARAMETER BaseUri
        QBO API origin. Default production 'https://quickbooks.api.intuit.com'.
    .PARAMETER StartDate
        Report period start (ISO date 'yyyy-MM-dd'). Defaults to the first day of the current month.
    .PARAMETER EndDate
        Report period end (ISO date 'yyyy-MM-dd'). Defaults to today (UTC).
    .PARAMETER MinorVersion
        QBO API minor version querystring. Confirm against the live app.
    .EXAMPLE
        Get-ImperionQboProfitAndLoss -StartDate '2026-06-01' -EndDate '2026-06-30'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId,
        [string] $BaseUri = 'https://quickbooks.api.intuit.com',
        [string] $StartDate,
        [string] $EndDate,
        [int] $MinorVersion = 70
    )

    $cfg = Get-ImperionConfig
    $names = Get-ImperionSecretNames
    if (-not $TenantId) { $TenantId = $cfg.LocalTenantId }

    $today = (Get-Date).ToUniversalTime()
    if (-not $StartDate) { $StartDate = (Get-Date -Year $today.Year -Month $today.Month -Day 1).ToString('yyyy-MM-dd') }
    if (-not $EndDate) { $EndDate = $today.ToString('yyyy-MM-dd') }
    # The snapshot grain is the report period; external_id = a stable period key for the upsert.
    $period = '{0}..{1}' -f $StartDate, $EndDate

    $accessToken = Get-ImperionSecretValue -Name $names.QboAccessToken
    $realmId = Get-ImperionSecretValue -Name $names.QboRealmId

    $uri = '{0}/v3/company/{1}/reports/ProfitAndLoss?start_date={2}&end_date={3}&minorversion={4}' -f `
        $BaseUri.TrimEnd('/'), [uri]::EscapeDataString($realmId), `
        [uri]::EscapeDataString($StartDate), [uri]::EscapeDataString($EndDate), $MinorVersion
    $headers = @{ Authorization = "Bearer $accessToken"; Accept = 'application/json' }

    $resp = Invoke-ImperionRestWithRetry -Uri $uri -Headers $headers -Method GET
    $report = $resp.Body

    # Walk the report Rows tree for a summary row whose ColData[0].value matches a label, returning
    # its trailing total cell. The P&L report is a nested Header/Rows/Summary tree; the headline
    # totals live in Summary rows (StrictMode-safe via Get-ImperionPropertyPath).
    $summaryTotal = {
        param($reportBody, [string[]] $labels)
        $rowsContainer = Get-ImperionPropertyPath -InputObject $reportBody -Path 'Rows.Row'
        foreach ($row in @($rowsContainer)) {
            if ($null -eq $row) { continue }
            $summaryCols = Get-ImperionPropertyPath -InputObject $row -Path 'Summary.ColData'
            $cols = @($summaryCols)
            if ($cols.Count -ge 2) {
                $label = [string](Get-ImperionPropertyPath -InputObject $cols[0] -Path 'value')
                foreach ($candidate in $labels) {
                    if ($label -and $label -match $candidate) {
                        return (Get-ImperionPropertyPath -InputObject $cols[-1] -Path 'value')
                    }
                }
            }
        }
        return $null
    }

    $firstOf = {
        param($record, [string[]] $candidates)
        foreach ($candidate in $candidates) {
            $value = Get-ImperionPropertyPath -InputObject $record -Path $candidate
            if ($null -ne $value -and "$value" -ne '') { return $value }
        }
    }

    # One snapshot row. external_id = the period; headline totals are surfaced for BI, the full
    # report lives in raw_payload. Column set mirrors front-end migration 0120 (qbo_profit_and_loss).
    $map = [ordered]@{
        period          = { $period }
        start_date      = { $StartDate }
        end_date        = { $EndDate }
        report_period   = { param($r) & $firstOf $r @('Header.ReportName', 'header.reportName') }
        currency        = { param($r) & $firstOf $r @('Header.Currency', 'header.currency') }
        total_income    = { param($r) & $summaryTotal $r @('^Total Income$', '^Income$', '^Total Revenue$') }
        total_expenses  = { param($r) & $summaryTotal $r @('^Total Expenses$', '^Expenses$') }
        net_income      = { param($r) & $summaryTotal $r @('^Net Income$', '^Net Operating Income$', '^Profit$') }
        generated_time  = { param($r) & $firstOf $r @('Header.Time', 'header.time') }
    }

    # external_id = the period key; the report has no entity Id, so feed the period as the id path
    # by stamping it onto a wrapper the flattener can resolve.
    $wrapped = $report | Add-Member -NotePropertyName '_period' -NotePropertyValue $period -PassThru -Force
    $wrapped | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'qbo' -TenantId $TenantId -ExternalIdProperty '_period'
}
