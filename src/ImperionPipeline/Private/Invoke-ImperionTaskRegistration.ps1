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
        Register-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Action $Action `
            -Trigger $Trigger -Settings $Settings -User $Credential.UserName `
            -Password $Credential.GetNetworkCredential().Password -RunLevel Highest -Force | Out-Null
    }
    else {
        Register-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -Action $Action `
            -Trigger $Trigger -Settings $Settings -Principal $Principal -Force | Out-Null
    }
}
