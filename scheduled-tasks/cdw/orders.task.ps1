# cdw/orders - daily CDW order/shipment/spend pull -> bronze (cdw_orders).
# Cadence: Daily (scheduled-tasks/README.md); procurement orders are slow-changing and the API is
# rate-limited per key, so one daily page-walk is well inside budget. Credential: SecretStore
# 'cdw-api-key' mirror, else Key Vault 'CDW-API-Key' via the cert SP (a COMPANY credential -
# Imperion's own purchasing account). Auth is an Authorization: Bearer header, so URLs are NOT
# secret-bearing.
#
# GATED (issue #198, ADR-0021): until the API key is reachable, the task logs the gap and exits
# cleanly - it never crashes the schedule. The front-end bronze migration 0120 (front-end #688) that
# defines cdw_orders is PROD-APPLIED; if the table were ever absent the post writer fails loudly
# (ADR-0005). Registration is deferred to the server bringup (#102), same as the other gated sources.
# Register with Register-ImperionTask (run elevated, under the local service identity):
#
#   Register-ImperionTask -Name 'Imperion cdw orders' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\cdw\orders.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

try {
    Get-ImperionCdwOrder | Set-ImperionCdwOrderToBronze
}
catch {
    # Credential / schema gate: an unreachable cdw-api-key / CDW-API-Key, or a missing cdw_orders
    # table, must not crash the schedule - log loudly and exit; the operator provisions/rotates the
    # key and the next run converges (idempotent upsert).
    Write-ImperionLog -Level Warn -Source 'cdw' -Message "CDW order sync skipped: $($_.Exception.Message)"
}
