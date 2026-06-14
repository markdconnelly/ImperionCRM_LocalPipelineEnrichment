function Get-ImperionAutotaskTimeEntry {
    <#
    .SYNOPSIS
        Collect Autotask TimeEntries and project them to typed autotask_time_entry bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for employee time tracking (front-end ADR-0082,
        migration 0086; LP epic #165, issue #171). This is the AUTHORITATIVE scheduled BULK
        pull — it owns the full/historical window. The cloud Pipeline PL-2
        (ImperionCRM_Pipeline#101) serves only the on-demand "refresh now" path; the
        bronze->silver `time_record` merge is PL-1 (ImperionCRM_Pipeline#100). Pages the
        TimeEntries entity via the shared Autotask context and projects each record. Returns
        rows; does not write. Requires Initialize-ImperionContext.

        TYPED TABLE — a first for this repo. Every other LP bronze table is text + jsonb, so
        the shared flatten helper (ConvertTo-ImperionFlatObject) coerces every cell to text.
        `autotask_time_entry` instead has typed columns (bigint / numeric / date / timestamptz),
        so this collector deliberately bypasses the text flattener and emits NATIVE CLR-typed
        values (long / decimal / DateOnly / DateTimeOffset). Npgsql maps those to the column
        types with no per-column SQL cast; the writer only casts payload_bronze ::jsonb.

        FIELD MAP (mirrors the PL-2 writer; confirm against the live API on first pull, recorded
        in docs/integrations/autotask-time-entry.md): id -> external_ref, resourceID ->
        autotask_resource_id, ticketID -> autotask_ticket_id, dateWorked -> work_date,
        startDateTime -> started_at, endDateTime -> ended_at, hoursWorked -> hours_worked,
        full payload -> payload_bronze. The collector NEVER emits app_user_id / matched_at —
        the merge owns employee resolution, so a re-ingested row stays resolved.

        DEPLOY-AHEAD: with no Autotask secrets in the SecretStore the shared
        Get-ImperionAutotaskContext throws on the unconfigured credential; the scheduled task
        wrapper treats that as a no-op (gates LIVE, not BUILD). No comp data, no PII logged.
    .PARAMETER SinceDays
        Incremental window on lastModifiedDateTime. Default 0 = full collection (the authoritative
        backfill). A positive value pulls only entries modified within that many days.
    .EXAMPLE
        Get-ImperionAutotaskTimeEntry -SinceDays 7 | Set-ImperionAutotaskTimeEntryToBronze
    .EXAMPLE
        # Full authoritative backfill:
        Get-ImperionAutotaskTimeEntry | Set-ImperionAutotaskTimeEntryToBronze
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [int] $SinceDays = 0
    )

    $ctx = Get-ImperionAutotaskContext
    $filter = if ($SinceDays -gt 0) {
        @{ op = 'gte'; field = 'lastModifiedDateTime'; value = (Get-Date).AddDays(-$SinceDays).ToString('yyyy-MM-ddTHH:mm:ssZ') }
    }
    else { @{ op = 'gte'; field = 'id'; value = 0 } }

    $records = Invoke-ImperionAutotaskRequest -ApiBaseUrl $ctx.ApiBase -Headers $ctx.Headers -Entity 'TimeEntries' -Filter $filter

    # First non-null/non-empty of a chain of plausible source names (StrictMode-safe).
    $firstOf = {
        param($record, [string[]] $candidates)
        foreach ($candidate in $candidates) {
            $value = Get-ImperionMember $record $candidate
            if ($null -ne $value -and "$value" -ne '') { return $value }
        }
    }

    # Native typed coercions: the bronze columns are typed, so emit CLR types Npgsql maps
    # directly (long->bigint, decimal->numeric, DateOnly->date, DateTimeOffset->timestamptz).
    # Each returns $null (-> DBNull at the upsert) on a missing/unparseable value.
    $asLong = {
        param($value)
        if ($null -eq $value -or "$value" -eq '') { return $null }
        $parsed = [long]0
        if ([long]::TryParse([string]$value, [ref] $parsed)) { return $parsed }
        return $null
    }
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
    $asTimestamp = {
        param($value)
        if ($null -eq $value -or "$value" -eq '') { return $null }
        $parsed = [datetimeoffset]::MinValue
        if ([datetimeoffset]::TryParse([string]$value, [ref] $parsed)) { return $parsed }
        return $null
    }

    foreach ($record in $records) {
        [pscustomobject][ordered]@{
            external_ref         = [string](& $firstOf $record @('id'))
            autotask_resource_id = & $asLong (& $firstOf $record @('resourceID', 'resourceId'))
            autotask_ticket_id   = & $asLong (& $firstOf $record @('ticketID', 'ticketId'))
            work_date            = & $asDate (& $firstOf $record @('dateWorked', 'workDate'))
            started_at           = & $asTimestamp (& $firstOf $record @('startDateTime', 'startTime'))
            ended_at             = & $asTimestamp (& $firstOf $record @('endDateTime', 'endTime'))
            hours_worked         = & $asDecimal (& $firstOf $record @('hoursWorked', 'hoursToBill'))
            payload_bronze       = ($record | ConvertTo-Json -Compress -Depth 20)
            last_seen_at         = [datetimeoffset]((Get-Date).ToUniversalTime())
        }
    }
}
