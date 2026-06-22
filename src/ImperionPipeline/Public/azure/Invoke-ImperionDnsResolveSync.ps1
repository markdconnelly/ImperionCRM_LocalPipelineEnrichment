function Invoke-ImperionDnsResolveSync {
    <#
    .SYNOPSIS
        Resolve the GUI-managed domain list from the public internet into dns_records bronze.
    .DESCRIPTION
        Thin orchestrator (CLAUDE.md §4, ADR-0007: cmdlet-first, no loose entry scripts) promoting
        scheduled-tasks/azure/dns-resolve.task.ps1. The public ground-truth plane (ADR-0063): reads the
        account_domain registry and resolves each (account, domain) from the public internet (no
        Microsoft auth), writing dns_records stamped with the owning account. GATED: until front-end
        migration 0081 (account_domain) is applied the read fails loudly; the catch logs a Warn and
        exits cleanly. Requires Initialize-ImperionContext.
    .EXAMPLE
        Invoke-ImperionDnsResolveSync
    #>
    [CmdletBinding()]
    param()

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
}
