function Invoke-ImperionAutotaskContractSync {
    <#
    .SYNOPSIS
        Collect Autotask contracts into the autotask_contracts bronze table (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) over the
        reusable get/post pair — Get-ImperionAutotaskContract collects + flattens, then
        Set-ImperionAutotaskContractToBronze upserts (change-detected, idempotent). Contracts are
        incremental on lastModifiedDateTime: the window comes from -SinceDays when bound, else the
        IMPERION_AUTOTASK_CONTRACT_SINCE_DAYS environment variable, else 7 days. Pass -SinceDays 0
        for a full backfill (the local pipeline owns the historical window). Requires
        Initialize-ImperionContext. Registered as the \Imperion\Imperion-AutotaskContracts task.
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant.
    .PARAMETER SinceDays
        Incremental window on lastModifiedDateTime. Omit to use IMPERION_AUTOTASK_CONTRACT_SINCE_DAYS
        (fallback 7); pass 0 for a full collection.
    .OUTPUTS
        The upsert tally { scanned; inserted; updated; unchanged }.
    .EXAMPLE
        Invoke-ImperionAutotaskContractSync
    .EXAMPLE
        Invoke-ImperionAutotaskContractSync -SinceDays 0   # full backfill
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId,
        [int] $SinceDays
    )

    if (-not $PSBoundParameters.ContainsKey('SinceDays')) {
        $SinceDays = if ($env:IMPERION_AUTOTASK_CONTRACT_SINCE_DAYS) {
            [int] $env:IMPERION_AUTOTASK_CONTRACT_SINCE_DAYS
        }
        else { 7 }
    }

    $started = Get-Date
    $getArgs = @{ SinceDays = $SinceDays }
    if ($TenantId) { $getArgs.TenantId = $TenantId }

    $tally = Get-ImperionAutotaskContract @getArgs | Set-ImperionAutotaskContractToBronze

    Write-ImperionLog -Level Metric -Source 'autotask' -Message 'Autotask contract sync complete.' -Data @{
        sinceDays = $SinceDays
        seconds   = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
    }
    $tally
}
