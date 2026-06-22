function Invoke-ImperionPax8SubscriptionSync {
    <#
    .SYNOPSIS
        Pull Pax8 subscriptions into the pax8_subscriptions bronze table (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007) for Pax8 (issue #279, epic #1042). Credential:
        the MSP-wide OAuth2 client-credentials pair resolved SecretStore-first / Key Vault-fallback
        (Resolve-ImperionPax8Credential). Idempotent upsert. Requires Initialize-ImperionContext;
        fails closed — an unprovisioned credential or a missing pax8_subscriptions table is logged
        (warn) and skipped, never crashing the schedule.
    .EXAMPLE
        Invoke-ImperionPax8SubscriptionSync
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    try {
        Get-ImperionPax8Subscription | Set-ImperionPax8SubscriptionToBronze
    }
    catch {
        Write-ImperionLog -Level Warn -Source 'pax8' -Message "Pax8 subscription sync skipped: $($_.Exception.Message)"
    }
}
