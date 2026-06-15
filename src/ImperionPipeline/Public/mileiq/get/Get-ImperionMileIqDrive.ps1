function Get-ImperionMileIqDrive {
    <#
    .SYNOPSIS
        Collect business-classified MileIQ drives per connected employee → typed mileiq_drive bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for employee mileage capture (front-end ADR-0083,
        migration 0089; LP epic #166, issue #167). This is the AUTHORITATIVE scheduled per-
        connected-employee pull of MILEAGE drives. Pure expense data: flattens STRAIGHT to
        Postgres and SKIPS the IT Glue hub. Returns rows; does not write. Requires
        Initialize-ImperionContext.

        PER-EMPLOYEE OAUTH (CLAUDE.md §1/§3). MileIQ is per-user read-only OAuth. The BACKEND
        owns the OAuth handshake and custodies each employee's refresh token in Key Vault; this
        repo only reads the short-lived ACCESS token the backend surfaces, per employee, via
        Resolve-ImperionMileIqAccessToken. The set of connected employees is read from the
        silver `employee_profile` (the email-resolved mileiq_user_id mapping, migration 0088):
        one MileIQ pull per row that has a mileiq_user_id. An employee with no resolvable token
        (not yet connected / consent revoked / custody not live) is SKIPPED cleanly — fail
        closed, never touch an unconnected identity (CLAUDE.md §3).

        BUSINESS-ONLY, NO COMP. Only business-classified drives are requested
        (?classification=business); PERSONAL DRIVES NEVER ENTER (ADR-0083). The captured fields
        are the non-comp mileage facts: drive_date, miles, origin, destination, and MileIQ's own
        `suggested_rate`/`suggested_amount` (its built-in IRS-style suggestion — NOT employee
        compensation; the front-end finance store owns any reimbursable rate). No comp data is
        read or written; nothing PII-bearing is logged (metric counts only, CLAUDE.md §8).

        app_user_id RESOLUTION. Each drive row carries the owning employee's `app_user_id`
        resolved from employee_profile.mileiq_user_id where present; when the mapping has no
        app_user_id yet, the column is left NULL and `last_seen_at` is stamped so the cloud
        Pipeline merge can resolve it later (the time-entry idiom, ADR-0082).

        TYPED TABLE (like autotask_time_entry). mileiq_drive has typed columns (numeric / date /
        timestamptz / bigint), so this collector bypasses the text flattener and emits NATIVE
        CLR-typed values (decimal / DateOnly / DateTimeOffset). Npgsql maps those to the column
        types with no per-column SQL cast; the writer only casts payload_bronze ::jsonb. The
        conflict key is `mileiq_drive_id` (the stable MileIQ drive id) — idempotent/resumable.

        DEPLOY-AHEAD / DORMANT. With no MileIQ credentials provisioned and no connected
        employees, every per-employee token resolves $null and the collector returns zero rows
        without throwing (the QBO/Plaud deploy-ahead idiom): the code ships now and runs live
        only once the credentials (markdconnelly/ImperionCRM#495) and backend OAuth custody land
        and migrations 0088-0090 are applied (markdconnelly/ImperionCRM#494; the mileiq_drive
        bronze table itself is the FE follow-up markdconnelly/ImperionCRM#590, filed from #167 —
        schema is front-end-owned, CLAUDE.md §1). See docs/integrations/mileiq.md.

        CONFIRM BEFORE LIVE USE: the MileIQ drives field names below, the base host, the
        business-classification filter value, and the paging shape are modeled from the
        documented API but UNVERIFIED until the credentials land. Each typed field leads with
        the documented name and keeps a short fallback chain; an unmatched field lands NULL and
        nothing is lost (full payload in payload_bronze).
    .PARAMETER SinceDays
        Incremental window on the drive date. Default 0 = full collection (the authoritative
        backfill — the local pipeline owns the historical window). A positive value pulls only
        drives on/after that many days ago.
    .PARAMETER BaseUri
        MileIQ API origin. Default 'https://api.mileiq.com'.
    .PARAMETER Connection
        Optional open Npgsql connection used ONLY to read the employee_profile mapping. When
        omitted, one is opened from config and disposed before returning. The collector never
        writes here.
    .EXAMPLE
        Get-ImperionMileIqDrive -SinceDays 7 | Set-ImperionMileIqDriveToBronze
    .EXAMPLE
        # Full authoritative backfill:
        Get-ImperionMileIqDrive | Set-ImperionMileIqDriveToBronze
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [int] $SinceDays = 0,
        [string] $BaseUri = 'https://api.mileiq.com',
        $Connection
    )

    # Read the connected-employee mapping (silver employee_profile, migration 0088). Only rows
    # with a mileiq_user_id are connectable; app_user_id may be NULL (merge resolves later).
    $ownsConnection = $false
    $activeConnection = $Connection
    if (-not $activeConnection) { $activeConnection = New-ImperionDbConnection; $ownsConnection = $true }
    try {
        $connectedEmployees = @(Invoke-ImperionDbQuery -Connection $activeConnection -Sql @'
SELECT mileiq_user_id, app_user_id
  FROM employee_profile
 WHERE mileiq_user_id IS NOT NULL
 ORDER BY mileiq_user_id
'@)
    }
    finally { if ($ownsConnection) { $activeConnection.Dispose() } }

    if ($connectedEmployees.Count -eq 0) {
        Write-ImperionLog -Source 'mileiq' -Message 'MileIQ drive pull: no employees with a mileiq_user_id mapping (dormant).'
        return
    }

    $startDate = if ($SinceDays -gt 0) { (Get-Date).AddDays(-$SinceDays).ToUniversalTime().ToString('yyyy-MM-dd') } else { $null }

    # First non-null/non-empty of a chain of plausible source names (StrictMode-safe).
    $firstOf = {
        param($record, [string[]] $candidates)
        foreach ($candidate in $candidates) {
            $value = Get-ImperionPropertyPath -InputObject $record -Path $candidate
            if ($null -ne $value -and "$value" -ne '') { return $value }
        }
    }

    # Native typed coercions: the bronze columns are typed, so emit CLR types Npgsql maps
    # directly (decimal->numeric, DateOnly->date). Each returns $null (-> DBNull) on a
    # missing/unparseable value.
    $asDecimal = {
        param($value)
        if ($null -eq $value -or "$value" -eq '') { return $null }
        $parsed = [decimal]0
        if ([decimal]::TryParse([string]$value, [ref] $parsed)) { return $parsed }
        return $null
    }
    $asDate = {
        param($value)
        if ($null -eq $value -or "$value" -eq '') { return $null }
        $parsed = [datetime]::MinValue
        if ([datetime]::TryParse([string]$value, [ref] $parsed)) { return [DateOnly]::FromDateTime($parsed) }
        return $null
    }

    foreach ($employee in $connectedEmployees) {
        $mileIqUserId = [string]$employee.mileiq_user_id
        $accessToken = Resolve-ImperionMileIqAccessToken -MileIqUserId $mileIqUserId
        if (-not $accessToken) {
            # Unconnected / consent-revoked / custody-not-live: skip this employee cleanly.
            Write-ImperionLog -Source 'mileiq' -Message "MileIQ drive pull: no token for a connected employee; skipped (dormant)."
            continue
        }

        # Business-classified ONLY — personal drives never enter (ADR-0083).
        $uri = '{0}/drives?classification=business' -f $BaseUri.TrimEnd('/')
        if ($startDate) { $uri += '&startDate=' + [uri]::EscapeDataString($startDate) }
        $drives = Invoke-ImperionMileIqRequest -AccessToken $accessToken -Uri $uri

        foreach ($drive in $drives) {
            [pscustomobject][ordered]@{
                mileiq_drive_id  = [string](& $firstOf $drive @('id', 'driveId', 'drive_id'))
                mileiq_user_id   = $mileIqUserId
                app_user_id      = $employee.app_user_id   # NULL ok — merge resolves later
                drive_date       = & $asDate (& $firstOf $drive @('driveDate', 'date', 'startDate', 'startTime'))
                miles            = & $asDecimal (& $firstOf $drive @('miles', 'distance', 'distanceMiles'))
                origin           = [string](& $firstOf $drive @('startLocation.name', 'origin', 'startName', 'startAddress'))
                destination      = [string](& $firstOf $drive @('endLocation.name', 'destination', 'endName', 'endAddress'))
                suggested_rate   = & $asDecimal (& $firstOf $drive @('suggestedRate', 'rate', 'mileageRate'))   # MileIQ's IRS-style suggestion (NOT comp)
                suggested_amount = & $asDecimal (& $firstOf $drive @('suggestedAmount', 'value', 'amount'))       # suggested reimbursement (NOT comp)
                payload_bronze   = ($drive | ConvertTo-Json -Compress -Depth 20)
                last_seen_at     = [datetimeoffset]((Get-Date).ToUniversalTime())
            }
        }
    }
}
