# azure/inventory - daily Azure inventory reconcile -> bronze (azure_subscriptions,
# azure_resource_groups, azure_resources). Cadence: Daily (scheduled-tasks/README.md).
# Composes the per-entity get + post pairs (CLAUDE.md §1): subscriptions first, then the
# resource groups and resources of each subscription. Management groups + Sentinel objects
# remain covered by the posture task (Invoke-ImperionAzureInventorySync) until the
# per-entity Sentinel get lands (docs/STATUS.md, Remaining #1); overlapping rows are
# change-detected upserts on the same keys, so running both stays idempotent.
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion azure inventory' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\azure\inventory.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

$subscriptionRows = @(Get-ImperionAzureSubscription)
$subscriptionRows | Set-ImperionAzureSubscriptionToBronze

foreach ($subscriptionId in @($subscriptionRows | ForEach-Object { $_.external_id })) {
    Get-ImperionAzureResourceGroup -SubscriptionId $subscriptionId | Set-ImperionAzureResourceGroupToBronze
    Get-ImperionAzureResource -SubscriptionId $subscriptionId | Set-ImperionAzureResourceToBronze
}
