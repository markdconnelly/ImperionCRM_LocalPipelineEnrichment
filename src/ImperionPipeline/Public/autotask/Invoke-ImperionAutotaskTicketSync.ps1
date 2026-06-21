function Invoke-ImperionAutotaskTicketSync {
    <#
    .SYNOPSIS
        Collect Autotask tickets into the autotask_tickets bronze table (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) over the
        reusable get/post pair — Get-ImperionAutotaskTicket collects + flattens, then
        Set-ImperionAutotaskTicketToBronze upserts (change-detected, idempotent). This is the
        scheduled BULK reconcile; real-time ticket webhooks stay in the cloud Pipeline (ADR-0001).
        Tickets are incremental on lastActivityDate: the window comes from -SinceDays when bound,
        else the IMPERION_AUTOTASK_TICKET_SINCE_DAYS environment variable, else 1 day. Pass
        -SinceDays 0 for a full collection. Requires Initialize-ImperionContext. Registered as the
        \Imperion\Imperion-AutotaskTickets task.
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant.
    .PARAMETER SinceDays
        Incremental window on lastActivityDate. Omit to use IMPERION_AUTOTASK_TICKET_SINCE_DAYS
        (fallback 1); pass 0 for a full collection.
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Invoke-ImperionAutotaskTicketSync
    .EXAMPLE
        Invoke-ImperionAutotaskTicketSync -SinceDays 0   # full backfill
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId,
        [int] $SinceDays
    )

    if (-not $PSBoundParameters.ContainsKey('SinceDays')) {
        $SinceDays = if ($env:IMPERION_AUTOTASK_TICKET_SINCE_DAYS) {
            [int] $env:IMPERION_AUTOTASK_TICKET_SINCE_DAYS
        }
        else { 1 }
    }

    $started = Get-Date
    $getArgs = @{ SinceDays = $SinceDays }
    if ($TenantId) { $getArgs.TenantId = $TenantId }

    $tally = Get-ImperionAutotaskTicket @getArgs | Set-ImperionAutotaskTicketToBronze

    Write-ImperionLog -Level Metric -Source 'autotask' -Message 'Autotask ticket sync complete.' -Data @{
        sinceDays = $SinceDays
        seconds   = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
    }
    $tally
}
