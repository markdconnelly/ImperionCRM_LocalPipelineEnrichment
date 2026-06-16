# amazonbusiness/orders - daily Amazon Business order/shipment/spend pull -> bronze (amazon_business_orders).
# Cadence: Daily (scheduled-tasks/README.md); procurement orders are slow-changing and the API is
# rate-limited per credential, so one daily page-walk is well inside budget. Credential: SecretStore
# 'amazon-business-token' mirror, else Key Vault 'AmazonBusiness-Token' via the cert SP (a COMPANY
# credential - Imperion's own purchasing account). Auth is an Authorization: Bearer header, so URLs
# are NOT secret-bearing.
#
# GATED (issue #198, ADR-0021): until the access token is reachable, the task logs the gap and exits
# cleanly - it never crashes the schedule. The front-end bronze migration 0120 (front-end #688) that
# defines amazon_business_orders is PROD-APPLIED; if the table were ever absent the post writer fails
# loudly (ADR-0005). Registration is deferred to the server bringup (#102), same as the other gated
# sources.
# Register with Register-ImperionTask (run elevated, under the local service identity):
#
#   Register-ImperionTask -Name 'Imperion amazonbusiness orders' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\amazonbusiness\orders.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

try {
    Get-ImperionAmazonBusinessOrder | Set-ImperionAmazonBusinessOrderToBronze
}
catch {
    # Credential / schema gate: an unreachable amazon-business-token / AmazonBusiness-Token, or a
    # missing amazon_business_orders table, must not crash the schedule - log loudly and exit; the
    # operator provisions/rotates the token and the next run converges (idempotent upsert).
    Write-ImperionLog -Level Warn -Source 'amazon_business' -Message "Amazon Business order sync skipped: $($_.Exception.Message)"
}
