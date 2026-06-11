function Register-ImperionTask {
    <#
    .SYNOPSIS
        Register (or refresh) the pipeline's Windows Scheduled Tasks — one per sync cmdlet (idempotent).
    .DESCRIPTION
        Each task runs the installed module's cmdlet under the dedicated gMSA/service account,
        "whether logged on or not", with overlap prevention. The task command imports the
        module, initializes context, and invokes one cmdlet. Re-running updates definitions in
        place. See docs/operations/scheduled-task-registry.md.
    .PARAMETER TaskIdentity
        gMSA/service account to run the tasks (e.g. 'DOMAIN\svc-imperion$').
    .PARAMETER PwshPath
        Path to pwsh.exe. Default resolves from PATH.
    .PARAMETER TaskFolder
        Task Scheduler folder. Default '\Imperion'.
    .EXAMPLE
        Register-ImperionTask -TaskIdentity 'CORP\svc-imperion$'
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string] $TaskIdentity,
        [string] $PwshPath = (Get-Command pwsh -ErrorAction SilentlyContinue).Source,
        [string] $TaskFolder = '\Imperion'
    )
    if (-not $PwshPath) { throw 'pwsh.exe not found on PATH; pass -PwshPath.' }

    $tasks = @(
        @{ Name = 'Imperion-EntraServicePrincipals'; Cmdlet = 'Invoke-ImperionServicePrincipalSync'; At = '02:00' }
        @{ Name = 'Imperion-AzureInventory';         Cmdlet = 'Invoke-ImperionAzureInventorySync';   At = '02:30' }
        @{ Name = 'Imperion-SecureScore';            Cmdlet = 'Invoke-ImperionSecureScoreSync';       At = '02:45' }
        @{ Name = 'Imperion-PolicySync';             Cmdlet = 'Invoke-ImperionPolicySync';            At = '03:00' }
        # Posture silver merge runs AFTER SecureScore (02:45) + PolicySync (03:00)
        # so it classifies the night's fresh bronze (ADR-0010, frontend ADR-0051).
        @{ Name = 'Imperion-PostureMerge';           Cmdlet = 'Invoke-ImperionPostureMerge';          At = '03:20' }
        # Snapshot runs daily AFTER the merge but self-gates to calendar quarters
        # (ADR-0011): the daily trigger just makes the quarter boundary self-healing.
        @{ Name = 'Imperion-PostureSnapshot';        Cmdlet = 'Invoke-ImperionPostureSnapshot';       At = '03:40' }
        @{ Name = 'Imperion-ITGlueExport';           Cmdlet = 'Invoke-ImperionITGlueExport';          At = '03:30' }
        @{ Name = 'Imperion-KaseyaImport';           Cmdlet = 'Invoke-ImperionKaseyaImport';          At = '01:00' }
        # Gold knowledge + vectorization runs LAST, after every ingest task above has
        # landed its data, so the embedded corpus reflects the night's loads (ADR-0009).
        @{ Name = 'Imperion-KnowledgeVectorize';     Cmdlet = 'Invoke-ImperionKnowledgeSync -Vectorize'; At = '04:30' }
    )

    $principal = New-ScheduledTaskPrincipal -UserId $TaskIdentity -LogonType Password -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable -DontStopOnIdleEnd -ExecutionTimeLimit (New-TimeSpan -Hours 4)

    foreach ($t in $tasks) {
        $command = "Import-Module ImperionPipeline; Initialize-ImperionContext; $($t.Cmdlet)"
        $argument = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command `"$command`""
        $action = New-ScheduledTaskAction -Execute $PwshPath -Argument $argument
        $trigger = New-ScheduledTaskTrigger -Daily -At $t.At

        if ($PSCmdlet.ShouldProcess($t.Name, 'Register scheduled task')) {
            Register-ScheduledTask -TaskName $t.Name -TaskPath $TaskFolder -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
            Write-Host "Registered $TaskFolder\$($t.Name) -> $($t.Cmdlet) @ $($t.At)"
        }
    }
    Write-Host "`nNote: gMSA principals use -LogonType Password with no stored password (managed by AD)."
}
