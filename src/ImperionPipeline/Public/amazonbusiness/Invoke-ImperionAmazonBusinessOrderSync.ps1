function Invoke-ImperionAmazonBusinessOrderSync {
    <#
    .SYNOPSIS
        Pull Amazon Business order/shipment/spend data into the amazon_business_orders bronze table (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/amazonbusiness/orders.task.ps1. Credential: SecretStore 'amazon-business-token'
        mirror, else Key Vault 'AmazonBusiness-Token' via the cert SP (a COMPANY credential — Imperion's
        own purchasing account); auth is an Authorization: Bearer header. Idempotent upsert. Requires
        Initialize-ImperionContext; fails closed — an unreachable token or a missing amazon_business_orders
        table is logged (warn) and skipped, never crashing the schedule (issue #198, ADR-0021).
    .EXAMPLE
        Invoke-ImperionAmazonBusinessOrderSync
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    try {
        Get-ImperionAmazonBusinessOrder | Set-ImperionAmazonBusinessOrderToBronze
    }
    catch {
        # Credential / schema gate: an unreachable amazon-business-token / AmazonBusiness-Token, or a
        # missing amazon_business_orders table, must not crash the schedule - log loudly and exit; the
        # operator provisions/rotates the token and the next run converges (idempotent upsert).
        Write-ImperionLog -Level Warn -Source 'amazon_business' -Message "Amazon Business order sync skipped: $($_.Exception.Message)"
    }
}
