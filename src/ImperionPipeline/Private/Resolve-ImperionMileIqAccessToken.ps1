function Resolve-ImperionMileIqAccessToken {
    <#
    .SYNOPSIS
        Resolve a per-employee MileIQ OAuth access token, or $null when that employee is unconnected.
    .DESCRIPTION
        Module-internal, PER-USER token resolution for the MileIQ drive pull (issue #167,
        ADR-0083 mileage capture). MileIQ is per-employee read-only OAuth: the BACKEND owns
        the OAuth handshake and custodies each employee's refresh token in Key Vault (backend
        MileIQ OAuth issue), then surfaces a short-lived ACCESS token per employee. This repo
        only READS that custodied token — it never holds a refresh token and never performs
        the OAuth dance (the system boundary: backend owns OAuth handshakes, CLAUDE.md §1).

        Resolution mirrors the KQM/Meta/Plaud token pattern but is keyed by the MileIQ user id
        so each employee resolves independently:
          1. an explicit -AccessToken wins (test / on-demand);
          2. else the SecretStore mirror titled `<MileIqTokenPrefix><MileIqUserId>` when the
             vault is unlocked this run (default prefix 'mileiq-token-');
          3. else the Key Vault secret titled `<MileIqTokenVaultPrefix><MileIqUserId>`
             (default 'MileIQ-Token-', the backend-custodied original in kv-imperioncrm-prd)
             read by the cert SP.

        DORMANT-PER-EMPLOYEE: when no token exists for an employee (not yet connected, consent
        revoked, or the backend custody is not live), this returns `$null` rather than throwing
        — the caller skips that employee cleanly so one unconnected user never fails the whole
        pull (fail-closed, CLAUDE.md §3/§8). The value is returned to the caller and never
        logged; the connect layer carries it as an Authorization: Bearer header (never a
        querystring), so it never reaches a log line.
    .PARAMETER MileIqUserId
        The MileIQ user id whose token to resolve (from employee_profile.mileiq_user_id).
    .PARAMETER AccessToken
        Optional explicit token override (wins over the vault). Held only in memory.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string] $MileIqUserId,
        [string] $AccessToken
    )

    if ($AccessToken) { return $AccessToken }
    $secretNames = Get-ImperionSecretNames

    $mirrorPrefix =
        if ($secretNames -is [System.Collections.IDictionary] -and $secretNames.Contains('MileIqTokenPrefix')) {
            $secretNames['MileIqTokenPrefix']
        }
        else { 'mileiq-token-' }
    $vaultPrefix =
        if ($secretNames -is [System.Collections.IDictionary] -and $secretNames.Contains('MileIqTokenVaultPrefix')) {
            $secretNames['MileIqTokenVaultPrefix']
        }
        else { 'MileIQ-Token-' }

    # A MISSING secret is the normal unconnected/dormant case, not an error: Get-Secret and
    # Get-ImperionKeyVaultSecret both THROW when the named secret does not exist, so each
    # lookup is wrapped and a throw is swallowed to $null. The caller treats $null as "skip
    # this employee" (dormant-per-employee). Real transport faults still surface via the next
    # employee's attempt and the task-level catch; we only suppress the not-found shape here.
    if ($script:ImperionSecretStoreVault) {
        try { $AccessToken = Get-ImperionSecretValue -Name ($mirrorPrefix + $MileIqUserId) }
        catch { $AccessToken = $null }
    }
    if (-not $AccessToken) {
        try { $AccessToken = Get-ImperionKeyVaultSecret -Name ($vaultPrefix + $MileIqUserId) }
        catch { $AccessToken = $null }
    }
    if ($AccessToken) { return $AccessToken }
    return $null
}
