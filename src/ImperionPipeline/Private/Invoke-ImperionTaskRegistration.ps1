function Resolve-ImperionLocalTaskUser {
    <#
    .SYNOPSIS
        Qualify a local service-account name so Register-ScheduledTask -User resolves it to a SID.
    .DESCRIPTION
        Register-ScheduledTask -User cannot map a '.\name' (or a bare local name) to a SID — it
        throws "No mapping between account names and security IDs was done". Rewrite a '.\name'
        or a bare 'name' to '<COMPUTERNAME>\name'; leave an already-qualified 'DOMAIN\name' or a
        UPN ('name@domain') untouched. Pure (no side effects) so it is unit-tested directly.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string] $UserName)

    if ($UserName -match '^\.\\(.+)$') { return "$env:COMPUTERNAME\$($Matches[1])" }
    if ($UserName -notmatch '[\\@]') { return "$env:COMPUTERNAME\$UserName" }
    return $UserName
}

function Invoke-ImperionTaskRegistration {
    <#
    .SYNOPSIS
        Thin seam over Register-ScheduledTask carrying the two registration modes.
    .DESCRIPTION
        gMSA principals register with -Principal and no stored password (AD manages
        it); a dedicated local service account (ADR-0012 — workgroup host, no gMSA)
        must register with -User/-Password so the task can run "whether user is
        logged on or not". Untyped parameters on purpose: Register-ScheduledTask
        binds CimInstance arguments even when mocked, so Pester observes this seam
        instead. The password is read from the PSCredential at call time and never
        logged, echoed, or placed in the task action.
    #>
    [CmdletBinding()]
    param(
        [string] $TaskName,
        [string] $TaskPath,
        $Action,
        $Trigger,
        $Settings,
        $Principal,
        [pscredential] $Credential
    )

    if ($Credential) {
        # Qualify a local '.\name'/bare name so -User resolves to a SID (Resolve-ImperionLocalTaskUser).
        # -ErrorAction Stop so the caller's per-task catch sees a genuine failure rather than a
        # swallowed non-terminating error (which previously printed "Registered" on failure).
        $user = Resolve-ImperionLocalTaskUser -UserName $Credential.UserName
        Register-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Action $Action `
            -Trigger $Trigger -Settings $Settings -User $user `
            -Password $Credential.GetNetworkCredential().Password -RunLevel Highest -Force `
            -ErrorAction Stop | Out-Null
    }
    else {
        Register-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Action $Action `
            -Trigger $Trigger -Settings $Settings -Principal $Principal -Force -ErrorAction Stop | Out-Null
    }
}
