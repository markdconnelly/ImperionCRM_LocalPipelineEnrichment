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
        # Autotask bulk reconcile -> bronze (#287). Tickets also arrive in real time via the cloud
        # Pipeline webhooks (ADR-0001); this is the daily catch-up. NOTE: the registry-doc cadence
        # for tickets is 15-30 min — the daily trigger here is a deliberate (documented) bulk
        # cadence until the $tasks schema gains sub-daily repetition (epic #286).
        @{ Name = 'Imperion-AutotaskContracts';      Cmdlet = 'Invoke-ImperionAutotaskContractSync'; At = '01:15' }
        @{ Name = 'Imperion-AutotaskTickets';        Cmdlet = 'Invoke-ImperionAutotaskTicketSync';    At = '01:30' }
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

        # === Collector catalog (epic #286): every remaining .task.ps1 promoted to a *Sync cmdlet
        # (ADR-0007, cmdlet-first) and registered here. Times stagger collectors BEFORE the merges
        # (03:10-03:44) and the gold vectorize (04:30). All are dormant-safe: each fails closed
        # (log + exit) on a missing credential row or unapplied bronze migration. The $tasks schema
        # is -Daily only; sub-daily cadences in scheduled-task-registry.md (tickets 15-30m, comms
        # hourly) register daily as bulk catch-up until a repetition field is added (#286). ===

        # QBO finance (read-only; dormant until qbo-access-token/realm provisioned)
        @{ Name = 'Imperion-QboAccounts';            Cmdlet = 'Invoke-ImperionQboAccountSync';            At = '00:00' }
        @{ Name = 'Imperion-QboCustomers';           Cmdlet = 'Invoke-ImperionQboCustomerSync';           At = '00:05' }
        @{ Name = 'Imperion-QboInvoices';            Cmdlet = 'Invoke-ImperionQboInvoiceSync';            At = '00:10' }
        @{ Name = 'Imperion-QboPayments';            Cmdlet = 'Invoke-ImperionQboPaymentSync';            At = '00:15' }
        @{ Name = 'Imperion-QboEstimates';           Cmdlet = 'Invoke-ImperionQboEstimateSync';           At = '00:20' }
        @{ Name = 'Imperion-QboBills';               Cmdlet = 'Invoke-ImperionQboBillSync';               At = '00:25' }
        @{ Name = 'Imperion-QboExpenseAccounts';     Cmdlet = 'Invoke-ImperionQboExpenseAccountSync';     At = '00:30' }
        @{ Name = 'Imperion-QboPurchases';           Cmdlet = 'Invoke-ImperionQboPurchaseSync';           At = '00:35' }
        @{ Name = 'Imperion-QboProfitAndLoss';       Cmdlet = 'Invoke-ImperionQboProfitAndLossSync';      At = '00:40' }
        # Operational / vendor integrations (dormant until each API key provisioned)
        @{ Name = 'Imperion-DattoRmmDevices';        Cmdlet = 'Invoke-ImperionDattoRmmDeviceSync';        At = '00:45' }
        @{ Name = 'Imperion-DattoBcdrBackups';       Cmdlet = 'Invoke-ImperionDattoBcdrBackupSync';       At = '00:50' }
        @{ Name = 'Imperion-MyItProcessRecs';        Cmdlet = 'Invoke-ImperionMyItProcessRecommendationSync'; At = '00:55' }
        @{ Name = 'Imperion-CdwOrders';              Cmdlet = 'Invoke-ImperionCdwOrderSync';              At = '01:05' }
        @{ Name = 'Imperion-AmazonBusinessOrders';   Cmdlet = 'Invoke-ImperionAmazonBusinessOrderSync';   At = '01:10' }
        @{ Name = 'Imperion-AutotaskTimeEntries';    Cmdlet = 'Invoke-ImperionAutotaskTimeEntrySync';     At = '01:20' }
        @{ Name = 'Imperion-KqmOpportunities';       Cmdlet = 'Invoke-ImperionKqmOpportunitySync';        At = '01:25' }
        @{ Name = 'Imperion-TelivyAssessments';      Cmdlet = 'Invoke-ImperionTelivyReportSync';          At = '01:35' }
        @{ Name = 'Imperion-DarkWebIdCompromises';   Cmdlet = 'Invoke-ImperionDarkWebIdCompromiseSync';   At = '01:40' }
        @{ Name = 'Imperion-EasyDmarcDomains';       Cmdlet = 'Invoke-ImperionEasyDmarcDomainSync';       At = '01:45' }
        @{ Name = 'Imperion-MileIqDrives';           Cmdlet = 'Invoke-ImperionMileIqDriveSync';           At = '01:50' }
        @{ Name = 'Imperion-PlaudRecordings';        Cmdlet = 'Invoke-ImperionPlaudRecordingSync';        At = '01:55' }
        @{ Name = 'Imperion-DocuSignEnvelopes';      Cmdlet = 'Invoke-ImperionDocuSignEnvelopeSync';      At = '02:05' }
        # Pax8 (company OAuth2 client-credentials; #279/#1042). Companies first — the join spine
        # the other three carry company_id against; the merge (#280) laterals on it.
        @{ Name = 'Imperion-Pax8Companies';          Cmdlet = 'Invoke-ImperionPax8CompanySync';           At = '02:06' }
        @{ Name = 'Imperion-Pax8Subscriptions';      Cmdlet = 'Invoke-ImperionPax8SubscriptionSync';      At = '02:07' }
        @{ Name = 'Imperion-Pax8Licenses';           Cmdlet = 'Invoke-ImperionPax8LicenseSync';           At = '02:08' }
        @{ Name = 'Imperion-Pax8Orders';             Cmdlet = 'Invoke-ImperionPax8OrderSync';             At = '02:09' }
        # AFTER the four Pax8 collectors: resolve pax8_companies -> account into entity_xref (#280, ADR-0026).
        @{ Name = 'Imperion-Pax8Merge';              Cmdlet = 'Invoke-ImperionPax8Merge';                 At = '02:10' }
        # IT Glue (company API key)
        @{ Name = 'Imperion-ITGlueOrganizations';    Cmdlet = 'Invoke-ImperionITGlueOrganizationSync';    At = '02:10' }
        @{ Name = 'Imperion-ITGlueContacts';         Cmdlet = 'Invoke-ImperionITGlueContactSync';         At = '02:12' }
        @{ Name = 'Imperion-ITGlueConfigurations';   Cmdlet = 'Invoke-ImperionITGlueConfigurationSync';   At = '02:14' }
        @{ Name = 'Imperion-UniFiDevices';           Cmdlet = 'Invoke-ImperionUniFiDeviceSync';           At = '02:20' }
        # AFTER the UniFi collector: merge unifi_devices -> silver device (network class) (#284, ADR-0026).
        @{ Name = 'Imperion-UniFiMerge';             Cmdlet = 'Invoke-ImperionUniFiMerge';                At = '02:22' }
        # Azure ARM resource inventory + Sentinel + DNS manage-plane (cert SP Reader)
        @{ Name = 'Imperion-AzureResourceInventory'; Cmdlet = 'Invoke-ImperionAzureResourceInventorySync'; At = '02:35' }
        @{ Name = 'Imperion-Sentinel';               Cmdlet = 'Invoke-ImperionSentinelSync';              At = '02:40' }
        @{ Name = 'Imperion-DnsZones';               Cmdlet = 'Invoke-ImperionDnsZoneSync';               At = '02:55' }
        # M365 estate — TENANT-OUTER driver (#359, ADR-0030 Decision #4). ONE job hydrates every
        # consented tenant: acquire each tenant's Graph token once, then run all 14 sweep-based
        # estate collectors pinned to that tenant (per-tenant fail-closed skip + per-routine
        # isolation + one Metric summary). Replaces the 14 per-collector M365 tasks (the
        # registry-as-enable fan-out, #358). Runs before the M365 directory merge (03:15) and
        # posture merge (03:20); ~18s/tenant keeps it inside that window for dozens of tenants.
        # NB this reverses §1 "one task per source" for the 365 estate plane only (ADR-0030) —
        # fail-isolation is preserved per (tenant, source) inside the driver. SecurityIncidents +
        # PurviewCompliance keep their own entries (not sweep-based collectors).
        @{ Name = 'Imperion-TenantHydration';        Cmdlet = 'Invoke-ImperionTenantHydration';           At = '03:02' }
        # AFTER the Intune collectors run inside TenantHydration (~03:02-03:05): fold
        # intune_managed_apps -> silver software_ci, resolving each install onto its silver device
        # (#354, ADR-0026).
        @{ Name = 'Imperion-SoftwareCiMerge';        Cmdlet = 'Invoke-ImperionSoftwareCiMerge';           At = '03:46' }
        @{ Name = 'Imperion-SecurityIncidents';      Cmdlet = 'Invoke-ImperionSecurityIncidentSync';      At = '03:36' }
        @{ Name = 'Imperion-PurviewCompliance';      Cmdlet = 'Invoke-ImperionPurviewComplianceSync';     At = '03:38' }
        # DNS public-resolve + silver merge (merge AFTER both DNS collectors)
        @{ Name = 'Imperion-DnsResolve';             Cmdlet = 'Invoke-ImperionDnsResolveSync';            At = '03:42' }
        @{ Name = 'Imperion-DnsMerge';               Cmdlet = 'Invoke-ImperionDnsMerge';                  At = '03:44' }
        # M365 communications (hourly target; daily bulk here)
        @{ Name = 'Imperion-M365Mail';               Cmdlet = 'Invoke-ImperionM365MailSync';              At = '03:46' }
        @{ Name = 'Imperion-M365TeamsChat';          Cmdlet = 'Invoke-ImperionM365TeamsChatSync';         At = '03:48' }
        @{ Name = 'Imperion-M365TeamsMeeting';       Cmdlet = 'Invoke-ImperionM365TeamsMeetingSync';      At = '03:50' }
        @{ Name = 'Imperion-ScopedInteractionMail';  Cmdlet = 'Invoke-ImperionScopedInteractionMailSync'; At = '03:52' }
        @{ Name = 'Imperion-ScopedInteractionTeams'; Cmdlet = 'Invoke-ImperionScopedInteractionTeamsSync'; At = '03:54' }
        # Meta (each *Sync runs Invoke-ImperionMetaMerge itself, ADR-0026). MetaSocial collects
        # FB posts/comments/DMs + IG media/comments/DMs (IG DMs LocalPipeline #361) in one run.
        @{ Name = 'Imperion-MetaSocial';             Cmdlet = 'Invoke-ImperionMetaSocialSync';            At = '04:00' }
        @{ Name = 'Imperion-MetaInsights';           Cmdlet = 'Invoke-ImperionMetaInsightSync';           At = '04:05' }
        # Lead Ads (leads_retrieval): forms + submitted leads -> bronze, then the co-located
        # lead_hook/lead_capture_event merge (LP #362). Dormant until the page token carries
        # leads_retrieval + migration 0207 is applied.
        @{ Name = 'Imperion-MetaLeadAds';            Cmdlet = 'Invoke-ImperionMetaLeadAdsSync';           At = '04:08' }
        # Threads (separate API graph.threads.net + own conn-company-threads token; LP #356,
        # front-end #1334/ADR-0125). One run collects our posts + replies + mentions + insights,
        # then runs Invoke-ImperionThreadsMerge itself (ADR-0026). Dormant until the connector is
        # seeded + the 6 App Review scopes clear + 0208 is applied (fail-closed log + exit).
        @{ Name = 'Imperion-Threads';                Cmdlet = 'Invoke-ImperionThreadsSync';               At = '04:12' }
        # Social plane slice H (#357, ADR-0124 #2/#9). Each *Sync self-collects its bronze then runs
        # its own merge (ADR-0026): SocialEngagement = FB/IG post comments + brand mentions (LP #391)
        # -> silver social_engagement; SocialMetric = post + (optional) ad insights -> silver
        # social_metric, metric names normalized at silver (#135). Both fail closed (log + exit) until
        # conn-company-meta + IMPERION_META_PAGE_ID are provisioned and 0075/0210/0212/0213 applied;
        # idempotent, so the next run converges. Run after the Meta collectors, before vectorize (04:30).
        @{ Name = 'Imperion-SocialEngagementSync';   Cmdlet = 'Invoke-ImperionSocialEngagementSync';      At = '04:18' }
        @{ Name = 'Imperion-SocialMetricSync';       Cmdlet = 'Invoke-ImperionSocialMetricSync';          At = '04:20' }
        # Housekeeping: 180-day security retention prune (after collectors) + weekly OKF drift (dry-run)
        @{ Name = 'Imperion-SecurityRetentionSweep'; Cmdlet = 'Invoke-ImperionSecurityRetentionSweep';    At = '04:10' }
        @{ Name = 'Imperion-SemanticDrift';          Cmdlet = 'Invoke-ImperionSemanticDriftSync';         At = '04:15' }

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
        # Wrap the cmdlet so an uncaught failure lands in the structured JSONL before the task
        # exits non-zero (#410). A scheduled, NonInteractive pwsh discards console output, so
        # without this a failed run leaves only LastTaskResult != 0 with no reason recorded.
        # Context is initialized first, so Write-ImperionLog has its log path; the rethrow
        # preserves the non-zero exit that surfaces the failure to Task Scheduler.
        $command = "Import-Module ImperionPipeline; Initialize-ImperionContext; try { $($t.Cmdlet) } catch { Write-ImperionLog -Level Error -Source 'task' -Message ('$($t.Name) failed: ' + (`$_.Exception.Message -replace '\s+', ' ')); throw }"
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
