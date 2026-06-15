# azure/dns-merge - daily DNS golden/drift silver merge -> dns_domain (issue #157 /
# front-end migration 0080 + 0081 + ADR-0063; local golden/drift ADR-0008). The silver
# half of DNS posture: reconciles the two capture planes (Azure manage plane dns_zones #155
# + public ground-truth plane dns_records #156) against the human-approved per-domain DNS
# Golden State (dns_golden, approved via Set-ImperionDnsGoldenState), classifies each
# domain's records (compliant/drift/ungoverned/missing), computes the three-state
# governance verdict (not-in-azure | in-azure-readonly | managed), and rolls every governed
# domain into dns_domain (verdict + drift counts + score).
#
# Runs AFTER the two collectors so it reconciles the freshest capture. Cadence: Daily
# (scheduled-tasks/README.md) - DNS drift is slow; the upsert is idempotent so re-runs are
# cheap and converge. The classification SQL is shared with the cloud on-demand refresh
# (parity contract, ADR-0063).
#
# GATED: until front-end migrations 0080 (dns_*) + 0081 (account_domain) are applied to
# prod the merge fails loudly; the catch below logs a Warn and exits cleanly so the
# schedule never crashes. No governed domains -> a clean no-op.
#
# NOTE: this task only MERGES captures against the golden baseline; approving a baseline is
# a separate HUMAN-gated step (Set-ImperionDnsGoldenState - see
# docs/operations/dns-golden-approval.md). Until a domain is approved every record reads
# 'ungoverned' - by design.
#
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion azure dns-merge' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\azure\dns-merge.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

try {
    Invoke-ImperionDnsMerge | Out-Null
}
catch {
    # Schema gate / transient: log loudly and exit; the next run converges (idempotent upsert).
    Write-ImperionLog -Level Warn -Source 'dns' -Message "DNS silver merge skipped: $($_.Exception.Message)"
}
