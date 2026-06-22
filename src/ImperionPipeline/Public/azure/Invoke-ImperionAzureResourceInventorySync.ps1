function Invoke-ImperionAzureResourceInventorySync {
    <#
    .SYNOPSIS
        Collect the Azure resource inventory (subscriptions -> resource groups -> resources) into bronze.
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/azure/inventory.task.ps1. Walks the per-entity get/post pairs: subscriptions
        first, then each subscription's resource groups + resources. Management groups + Sentinel stay
        with Invoke-ImperionAzureInventorySync until the per-entity Sentinel get lands; overlapping rows
        are change-detected upserts on the same keys, so running both stays idempotent. Requires
        Initialize-ImperionContext.
    .EXAMPLE
        Invoke-ImperionAzureResourceInventorySync
    #>
    [CmdletBinding()]
    param()

    $subscriptionRows = @(Get-ImperionAzureSubscription)
    $subscriptionRows | Set-ImperionAzureSubscriptionToBronze

    foreach ($subscriptionId in @($subscriptionRows | ForEach-Object { $_.external_id })) {
        Get-ImperionAzureResourceGroup -SubscriptionId $subscriptionId | Set-ImperionAzureResourceGroupToBronze
        Get-ImperionAzureResource -SubscriptionId $subscriptionId | Set-ImperionAzureResourceToBronze
    }
}
