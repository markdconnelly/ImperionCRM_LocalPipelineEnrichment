function Register-ImperionTask {
    <#
    .SYNOPSIS
        Register (or refresh) the pipeline's Windows Scheduled Tasks — one per sync cmdlet (idempotent).
    .DESCRIPTION
        Each task runs the installed module's cmdlet under the dedicated service
        identity, "whether logged on or not", with overlap prevention. The task command
        imports the module, initializes context, and invokes one cmdlet. Re-running
        updates definitions in place. Two identity modes (ADR-0012):

          -TaskIdentity   gMSA (domain-joined hosts): registers a principal with no
                          stored password — AD manages the credential.
          -TaskCredential dedicated LOCAL service account (this host: workgroup, no
                          gMSA possible — '.\svc-imperion'): registers with stored
                          credentials, which Task Scheduler requires for an
                          unattended local account. The password is never logged and
                          never appears in the task action.

        See docs/operations/scheduled-task-registry.md.
    .PARAMETER TaskIdentity
        gMSA to run the tasks (e.g. 'DOMAIN\svc-imperion$'). gMSA mode only.
    .PARAMETER TaskCredential
        Credential of the dedicated local service account (e.g. '.\svc-imperion').
        Local-account mode only — create the account with build/New-ImperionServiceAccount.ps1.
    .PARAMETER PwshPath
        Path to pwsh.exe. Default resolves from PATH.
    .PARAMETER TaskFolder
        Task Scheduler folder. Default '\Imperion'.
    .EXAMPLE
        Register-ImperionTask -TaskIdentity 'CORP\svc-imperion$'
    .EXAMPLE
        Register-ImperionTask -TaskCredential (Get-Credential '.\svc-imperion')
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Gmsa')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Gmsa')][string] $TaskIdentity,
        [Parameter(Mandatory, ParameterSetName = 'Credential')][pscredential] $TaskCredential,
        [string] $PwshPath = (Get-Command pwsh -ErrorAction SilentlyContinue).Source,
        [string] $TaskFolder = '\Imperion'
    )
    if (-not $PwshPath) { throw 'pwsh.exe not found on PATH; pass -PwshPath.' }

    $tasks = @(
        @{ Name = 'Imperion-EntraServicePrincipals'; Cmdlet = 'Invoke-ImperionServicePrincipalSync'; At = '02:00' }
        @{ Name = 'Imperion-AzureInventory';         Cmdlet = 'Invoke-ImperionAzureInventorySync';   At = '02:30' }
        # Per-client Azure ARM cloud-resource inventory → CMDB cloud-asset bronze (#201/#234,
        # ADR-0023). Fans out over every account_tenant; distinct from AzureInventory (partner tenant).
        @{ Name = 'Imperion-CloudResources';         Cmdlet = 'Invoke-ImperionCloudResourceSync';    At = '02:50' }
        @{ Name = 'Imperion-SecureScore';            Cmdlet = 'Invoke-ImperionSecureScoreSync';       At = '02:45' }
        @{ Name = 'Imperion-PolicySync';             Cmdlet = 'Invoke-ImperionPolicySync';            At = '03:00' }
        # Bronze→silver merges that co-locate with on-prem ingestion (ADR-0026). Each runs
        # AFTER its collector: CloudAssetMerge after CloudResources (02:50); M365DirectoryMerge
        # after the M365 user/group collectors. Both are idempotent and cede the cloud copies
        # (pipeline #134/#135) once verified in prod.
        @{ Name = 'Imperion-CloudAssetMerge';        Cmdlet = 'Invoke-ImperionCloudAssetMerge';       At = '03:10' }
        @{ Name = 'Imperion-M365DirectoryMerge';     Cmdlet = 'Invoke-ImperionM365DirectoryMerge';    At = '03:15' }
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

    $principal = $null
    if ($PSCmdlet.ParameterSetName -eq 'Gmsa') {
        $principal = New-ScheduledTaskPrincipal -UserId $TaskIdentity -LogonType Password -RunLevel Highest
    }
    $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable -DontStopOnIdleEnd -ExecutionTimeLimit (New-TimeSpan -Hours 4)

    foreach ($t in $tasks) {
        $command = "Import-Module ImperionPipeline; Initialize-ImperionContext; $($t.Cmdlet)"
        $argument = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command `"$command`""
        $action = New-ScheduledTaskAction -Execute $PwshPath -Argument $argument
        $trigger = New-ScheduledTaskTrigger -Daily -At $t.At

        if ($PSCmdlet.ShouldProcess($t.Name, 'Register scheduled task')) {
            # Report success only on success: the seam makes Register-ScheduledTask terminating
            # (-ErrorAction Stop), so a failed task is surfaced loudly and the loop continues to
            # the rest instead of masking a total failure as "Registered".
            try {
                Invoke-ImperionTaskRegistration -TaskName $t.Name -TaskPath $TaskFolder -Action $action `
                    -Trigger $trigger -Settings $settings -Principal $principal -Credential $TaskCredential
                Write-Host "Registered $TaskFolder\$($t.Name) -> $($t.Cmdlet) @ $($t.At)"
            }
            catch {
                Write-Warning "Failed to register $TaskFolder\$($t.Name): $($_.Exception.Message)"
            }
        }
    }
    if ($PSCmdlet.ParameterSetName -eq 'Gmsa') {
        Write-Host "`nNote: gMSA principals use -LogonType Password with no stored password (managed by AD)."
    }
    else {
        Write-Host "`nNote: local-account tasks store the credential with Task Scheduler (ADR-0012); a password change requires re-running Register-ImperionTask."
    }
}
