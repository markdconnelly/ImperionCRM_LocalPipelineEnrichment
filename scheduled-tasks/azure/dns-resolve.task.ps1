# azure/dns-resolve - daily public DNS posture resolution -> bronze (dns_records, plane
# 'public'; issue #156 / front-end migration 0080 + 0081 + ADR-0063). The ground-truth
# plane: resolves each domain in the GUI-managed account_domain list (SPF/DKIM/DMARC/MX/
# NS/A/CAA) from the public internet, so we see what the world sees and can cover domains
# NOT hosted in Azure DNS. The Azure manage plane is azure/dns-zones (#155); the golden/
# drift merge is local #157.
#
# Cadence: Daily (scheduled-tasks/README.md) - DNS drift is slow; change-detected upsert
# keeps re-runs cheap. Reads the account_domain registry (Mark's model: each customer has
# a GUI-managed list of domains, ADR-0063 amendment #334), resolves per (account, domain),
# writes dns_records stamped with the owning account. No Microsoft auth - pure public
# resolution (OS resolver + DoH fallback), so no GDAP/per-client dependency.
#
# GATED: until front-end migration 0081 (account_domain) is applied to prod the read fails
# loudly; the catch below logs a Warn and exits cleanly so the schedule never crashes. An
# empty list simply does nothing.
#
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion azure dns-resolve' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\azure\dns-resolve.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

try {
    $connection = New-ImperionDbConnection
    try {
        $trackedDomains = Invoke-ImperionDbQuery -Connection $connection `
            -Sql 'SELECT account_id, domain FROM account_domain ORDER BY account_id, domain'
        foreach ($tracked in $trackedDomains) {
            Get-ImperionDnsResolveObject -Domain ([string]$tracked.domain) -AccountId ([string]$tracked.account_id) |
                Set-ImperionDnsRecordToBronze -Connection $connection
        }
    }
    finally { $connection.Dispose() }
}
catch {
    # Schema gate / transient: log loudly and exit; the next run converges (idempotent,
    # change-detected upsert).
    Write-ImperionLog -Level Warn -Source 'dns' -Message "Public DNS resolve sync skipped: $($_.Exception.Message)"
}
