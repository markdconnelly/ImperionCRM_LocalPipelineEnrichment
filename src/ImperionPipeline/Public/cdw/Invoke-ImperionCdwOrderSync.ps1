function Invoke-ImperionCdwOrderSync {
    <#
    .SYNOPSIS
        Pull CDW order/shipment/spend data into the cdw_orders bronze table (scheduled-task entry point).
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/cdw/orders.task.ps1. Credential: SecretStore 'cdw-api-key' mirror, else Key
        Vault 'CDW-API-Key' via the cert SP (a COMPANY credential — Imperion's own purchasing account);
        auth is an Authorization: Bearer header. Idempotent upsert. Requires Initialize-ImperionContext;
        fails closed — an unreachable key or a missing cdw_orders table is logged (warn) and skipped,
        never crashing the schedule (issue #198, ADR-0021).
    .EXAMPLE
        Invoke-ImperionCdwOrderSync
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    try {
        Get-ImperionCdwOrder | Set-ImperionCdwOrderToBronze
    }
    catch {
        # Credential / schema gate: an unreachable cdw-api-key / CDW-API-Key, or a missing cdw_orders
        # table, must not crash the schedule - log loudly and exit; the operator provisions/rotates the
        # key and the next run converges (idempotent upsert).
        Write-ImperionLog -Level Warn -Source 'cdw' -Message "CDW order sync skipped: $($_.Exception.Message)"
    }
}
