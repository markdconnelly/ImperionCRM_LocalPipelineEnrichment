# azure/dns-zones - daily Azure DNS posture pull -> bronze (dns_zones + dns_records,
# plane 'azure'; issue #155 / front-end migration 0080 + ADR-0063). The manage plane of
# DNS posture: enumerates Microsoft.Network/dnsZones across every subscription the cert SP
# can read (Reader), proves write access per zone (the 'manageable' check, read-only), and
# captures the authoritative recordsets. Public-plane resolution is the sibling collector
# (azure/dns-resolve, #156); the golden/drift merge is local #157.
#
# Cadence: Daily (scheduled-tasks/README.md) - DNS drift is slow; the change-detected
# upsert keeps re-runs cheap. Composes Get-ImperionAzureSubscription -> per-sub get + post
# (CLAUDE.md §1). Auth is the module's cert-SP ARM token (Reader, already held - NO new
# grant; the write-probe only READS the Authorization permissions endpoint).
#
# GATED: until front-end migration 0080 is applied to prod the post fails loudly; the catch
# below logs a Warn and exits cleanly so the schedule never crashes.
#
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion azure dns-zones' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\azure\dns-zones.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

try {
    $subscriptionRows = @(Get-ImperionAzureSubscription)
    foreach ($subscriptionId in @($subscriptionRows | ForEach-Object { $_.external_id })) {
        Get-ImperionDnsZoneObject -SubscriptionId $subscriptionId | Set-ImperionDnsZoneToBronze
    }
}
catch {
    # Schema/permission gate: log loudly and exit; the operator lands the 0080 prod apply
    # and the next run converges (idempotent, change-detected upsert).
    Write-ImperionLog -Level Warn -Source 'dns' -Message "Azure DNS posture sync skipped: $($_.Exception.Message)"
}
