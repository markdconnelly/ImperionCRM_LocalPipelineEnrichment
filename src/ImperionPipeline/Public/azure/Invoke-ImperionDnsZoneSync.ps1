function Invoke-ImperionDnsZoneSync {
    <#
    .SYNOPSIS
        Collect the Azure DNS manage plane (zones + records) into bronze (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/azure/dns-zones.task.ps1. Enumerates Microsoft.Network/dnsZones across every
        subscription the cert SP can read (Reader, no new grant) and captures the authoritative
        recordsets (ADR-0063). GATED: until front-end migration 0080 is applied the post fails loudly;
        the catch logs a Warn and exits cleanly so the schedule never crashes. Requires
        Initialize-ImperionContext.
    .EXAMPLE
        Invoke-ImperionDnsZoneSync
    #>
    [CmdletBinding()]
    param()

    try {
        $subscriptionRows = @(Get-ImperionAzureSubscription)
    }
    catch {
        # Schema/permission gate at enumerate time: log loudly and exit; the operator lands the
        # 0080 prod apply and the next run converges (idempotent, change-detected upsert).
        Write-ImperionLog -Level Warn -Source 'dns' -Message "Azure DNS posture sync skipped: $($_.Exception.Message)"
        return
    }

    foreach ($subscriptionId in @($subscriptionRows | ForEach-Object { $_.external_id })) {
        try {
            Get-ImperionDnsZoneObject -SubscriptionId $subscriptionId | Set-ImperionDnsZoneToBronze
        }
        catch {
            # Isolate per subscription: one subscription's dnsZones list can fail (e.g. HTTP 400
            # when the DNS resource provider isn't registered) — log + continue so the remaining
            # subscriptions still collect, instead of aborting the whole sweep (#339; §6).
            Write-ImperionLog -Level Warn -Source 'dns' -Message "DNS zone sync skipped for subscription '$subscriptionId': $($_.Exception.Message)"
        }
    }
}
