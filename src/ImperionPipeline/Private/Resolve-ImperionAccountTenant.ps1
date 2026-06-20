function Resolve-ImperionAccountTenant {
    <#
    .SYNOPSIS
        Resolve the owning-tenant isolation key for a managed-client `account` — the account's
        Microsoft tenant when one is mapped, else the account id itself.
    .DESCRIPTION
        Some sources are keyed on the customer `account` rather than a Microsoft tenant
        (UniFi consoles, #259). Their bronze envelope is still `tenant_id`-partitioned, so a
        per-account sweep needs a stable, always-present isolation value to stamp.

        This reads the front-end-owned `account_tenant` registry (ADR-0051; the local pipeline
        has read-only SELECT, migration 0141): if the account maps to a Microsoft tenant the
        tenant id is returned (so the account-scoped rows align with that client's M365/Azure
        data under one `tenant_id`); if it does not, the account id is returned so the stamp is
        ALWAYS present, isolated, and never the partner tenant. Returns a string either way.
    .PARAMETER Connection
        An open Npgsql connection (as Invoke-ImperionDbQuery).
    .PARAMETER AccountId
        The owning customer `account` id (uuid).
    .EXAMPLE
        $tenantId = Resolve-ImperionAccountTenant -Connection $conn -AccountId $row.account_id
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] $Connection,
        [Parameter(Mandatory)][string] $AccountId
    )

    $row = Invoke-ImperionDbQuery -Connection $Connection -Sql @'
SELECT tenant_id FROM account_tenant
WHERE account_id = @account::uuid AND tenant_id IS NOT NULL
ORDER BY tenant_id
LIMIT 1
'@ -Parameters @{ account = $AccountId } | Select-Object -First 1

    if ($row -and $row.tenant_id) { return [string]$row.tenant_id }
    return $AccountId
}
