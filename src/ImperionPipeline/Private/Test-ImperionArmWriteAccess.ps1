function Test-ImperionArmWriteAccess {
    <#
    .SYNOPSIS
        Decide whether the current ARM token's identity can WRITE at a given scope.
    .DESCRIPTION
        Private write-access probe behind the DNS-posture 'manageable' check (front-end
        ADR-0063). Reads the caller's OWN effective permissions at the scope via the
        Authorization 'permissions' endpoint — so there is no principal-object-id lookup,
        no hand-interpretation of role assignments, and role inheritance is already
        resolved server-side. Returns $true only when a granted action covers the target
        write action and no notAction removes it — proof of write, never assumption.

        Read-only: this issues GETs against the permissions endpoint and never mutates the
        scope. ARM action globs use '*' as a wildcard across the '/'-segmented action
        string (e.g. 'Microsoft.Network/*' or '*'); the matcher honours that.
    .PARAMETER Scope
        ARM resource id to probe (e.g. a Microsoft.Network/dnsZones resource id).
    .PARAMETER AccessToken
        ARM access token (resource https://management.azure.com/.default).
    .PARAMETER WriteAction
        The control-plane action that proves write. Defaults to the DNS recordset write.
    .OUTPUTS
        [bool] — true when the caller can perform WriteAction at Scope.
    .EXAMPLE
        Test-ImperionArmWriteAccess -Scope $zoneId -AccessToken $token
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string] $Scope,
        [Parameter(Mandatory)][string] $AccessToken,
        [string] $WriteAction = 'Microsoft.Network/dnsZones/recordSets/write'
    )

    # ARM action glob -> regex: escape, then turn the escaped '*' back into '.*'. Case-insensitive.
    $actionMatches = {
        param($pattern, $action)
        if ([string]::IsNullOrWhiteSpace($pattern)) { return $false }
        $regex = '^' + ([regex]::Escape($pattern) -replace '\\\*', '.*') + '$'
        return [bool]([regex]::Match($action, $regex, 'IgnoreCase').Success)
    }

    $permissions = Invoke-ImperionArmRequest `
        -Path "$Scope/providers/Microsoft.Authorization/permissions?api-version=2022-04-01" `
        -AccessToken $AccessToken

    foreach ($permission in $permissions) {
        $actions = @(Get-ImperionMember $permission 'actions')
        $notActions = @(Get-ImperionMember $permission 'notActions')
        $granted = $actions | Where-Object { & $actionMatches $_ $WriteAction }
        if (-not $granted) { continue }
        $revoked = $notActions | Where-Object { & $actionMatches $_ $WriteAction }
        if (-not $revoked) { return $true }   # granted and not negated at this scope
    }
    return $false
}
