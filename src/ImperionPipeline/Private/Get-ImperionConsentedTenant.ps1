function Get-ImperionConsentedTenant {
    <#
    .SYNOPSIS
        Enumerate the Microsoft tenants this node should hydrate — the GUI-mapped,
        credentialed tenants in the `connection` / `account_tenant` registry.
    .DESCRIPTION
        The single source of truth for "which tenants do we sweep" (epic #324 slice 3,
        ADR-0030 Decision #4). LP has no inbound surface and is pull/registry-driven
        (CLAUDE.md §1): a credential saved in the GUI writes a `connection` row + Key Vault
        secret and the tenant is mapped to its account in `account_tenant`; this helper
        discovers that on the next run, so **GUI-save is the enable** — no host env edit, no
        push/trigger.

        Returns the DISTINCT `account_tenant.tenant_id` for every account that has an active
        scope-agnostic `m365` `connection` row — i.e. every consented tenant, Imperion (the
        client-zero onboarding app) included, with no home special-case. Fan-out callers
        (`Invoke-ImperionM365EstateSweep`) iterate the list and fail-isolate per tenant, so a
        tenant whose credential is later revoked simply stops appearing here / fails closed in
        the token seam (CLAUDE.md §3) — never a cross-tenant read.

        Read-only SELECT over the front-end-owned registry (the LP role has SELECT on
        `account_tenant` [migration 0141] and `connection`). `provider`/`status` are inlined
        literals (not bound parameters) so the `connection_provider` enum resolves cleanly —
        the 42883 text-vs-enum cast pitfall (#330) only bites parameterized values.
    .PARAMETER Connection
        An optional open Npgsql connection (as Invoke-ImperionDbQuery). When omitted a
        transient connection is opened and disposed here.
    .OUTPUTS
        [string[]] — the consented tenant ids (possibly empty when nothing is mapped yet,
        which the caller treats as dormant-safe: the partner tenant only).
    .EXAMPLE
        $tenants = Get-ImperionConsentedTenant
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        $Connection
    )

    $ownConnection = -not $Connection
    if ($ownConnection) { $Connection = New-ImperionDbConnection }
    try {
        $rows = Invoke-ImperionDbQuery -Connection $Connection -Sql @'
SELECT DISTINCT t.tenant_id
FROM account_tenant t
JOIN connection c ON c.account_id = t.account_id
WHERE c.provider = 'm365' AND c.status = 'active' AND t.tenant_id IS NOT NULL
ORDER BY t.tenant_id
'@
        return @($rows | ForEach-Object { [string]$_.tenant_id } | Where-Object { $_ })
    }
    finally {
        if ($ownConnection) { $Connection.Dispose() }
    }
}
