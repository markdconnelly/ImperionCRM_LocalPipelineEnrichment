#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Applications

<#
.SYNOPSIS
    Create (or update) the read-only "Imperion Client Onboarding" Entra application in a
    client tenant and grant it the Microsoft Graph APPLICATION permissions the Imperion
    pipeline needs to READ that tenant's estate. Run by a Global Administrator IN the
    target client tenant.

.DESCRIPTION
    Per-client app model (backend ADR-0076 / credential registry ADR-0103 / LP ADR-0028).
    Each client tenant gets its OWN app registration; its `client_id` + secret are then
    seeded into the Imperion GUI credential registry (a `connection` row, scope=client) so
    the on-prem pipeline can mint a per-client token via `Resolve-ImperionTenantCredential`
    (LP #257) and read that tenant READ-ONLY.

    What this script does, idempotently:
      1. Connects to Microsoft Graph as a Global Admin of the target tenant.
      2. Resolves every requested permission NAME to its Graph app-role id AT RUNTIME from
         the tenant's Microsoft Graph service principal — NO hard-coded GUIDs. A name that
         does not resolve is warned and skipped; the wrong role is never granted.
      3. Creates (or reuses, by display name) the application + its service principal.
      4. Sets the app's requiredResourceAccess to the resolved read-only roles.
      5. Grants admin consent (app-role assignments on the app's service principal) —
         skipping any assignment that already exists.
      6. Creates a client secret and prints it ONCE.

    READ-ONLY by construction: every permission in $ReadOnlyPermissions is a `*.Read[.All]`
    application role. Mailbox / Teams MESSAGE-BODY reads are a separate, gated, protected
    grant and are intentionally NOT here (see $GatedCommsPermissions and -IncludeComms).

.PARAMETER TenantId
    The client tenant (GUID or domain) to onboard. Passed to Connect-MgGraph. If omitted,
    Connect-MgGraph prompts and uses whatever tenant you sign in to.

.PARAMETER DisplayName
    App registration display name. Default "Imperion Client Onboarding".

.PARAMETER SecretValidMonths
    Client-secret lifetime in months (default 24). Track rotation in the registry.

.PARAMETER IncludeComms
    ALSO request the gated communications-read roles ($GatedCommsPermissions: Mail.Read,
    Chat.Read.All, ChannelMessage.Read.All, OnlineMeetings.Read.All, CallRecords.Read.All).
    OFF by default — these are protected APIs needing extra Microsoft approval and are only
    used by the scoped-interaction collector (LP ADR-0022, dormant). Do not enable unless
    that capability is being turned on for this client.

.PARAMETER UseCertificate
    Instead of a client secret, upload the PUBLIC key of -CertificatePath as the app
    credential (the private key stays on the Imperion host / is generated separately).
    Cert auth is preferred long-term; a secret is simpler to seed. Mutually exclusive with
    the secret output.

.PARAMETER CertificatePath
    Path to a .cer (public key) to upload when -UseCertificate is set.

.EXAMPLE
    .\New-ImperionClientOnboardingApp.ps1 -TenantId contoso.onmicrosoft.com
    # Sign in as Contoso Global Admin; creates the app, grants read-only consent, prints a secret.

.EXAMPLE
    .\New-ImperionClientOnboardingApp.ps1 -TenantId <guid> -WhatIf
    # Show exactly what would be created/granted without changing anything.

.NOTES
    Requires the Microsoft.Graph PowerShell SDK:
        Install-Module Microsoft.Graph -Scope CurrentUser
    The secret value is shown ONCE and never written to disk or the Imperion logs. Copy it
    straight into the Imperion GUI credential entry (Settings -> Credentials), which custodies
    it in Key Vault — it is never stored in the database (CLAUDE.md token model).
#>
[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Secret')]
param(
    [string] $TenantId,
    [string] $DisplayName = 'Imperion Client Onboarding',
    [Parameter(ParameterSetName = 'Secret')][ValidateRange(1, 24)][int] $SecretValidMonths = 24,
    [switch] $IncludeComms,
    [Parameter(ParameterSetName = 'Certificate', Mandatory)][switch] $UseCertificate,
    [Parameter(ParameterSetName = 'Certificate', Mandatory)][string] $CertificatePath
)

$ErrorActionPreference = 'Stop'
$GraphAppId = '00000003-0000-0000-c000-000000000000'   # Microsoft Graph (well-known, stable)

# The read-only estate/posture permission set the pipeline collectors need. Names only —
# the script resolves each to its app-role id from THIS tenant's Graph SP at run time, so
# there are no GUIDs to drift. Keep this list in sync with the bronze catalog (CLAUDE.md §5).
$ReadOnlyPermissions = @(
    'User.Read.All'                              # m365 users -> m365_contacts
    'Group.Read.All'                             # entra groups -> m365_groups
    'GroupMember.Read.All'                       # group membership edges -> m365_group_members
    'Directory.Read.All'                         # org / domains -> entra_domains
    'Device.Read.All'                            # entra devices -> m365_devices
    'DeviceManagementManagedDevices.Read.All'    # Intune devices -> intune_managed_devices
    'DeviceManagementApps.Read.All'              # Intune managed apps -> intune_managed_apps
    'DeviceManagementConfiguration.Read.All'     # Intune config/security -> intune_security_policies, device_configuration_policies
    'DeviceManagementServiceConfig.Read.All'     # Autopilot profiles -> autopilot_policies
    'SecurityEvents.Read.All'                    # Secure Score + Defender -> secure_scores, defender_*
    'Policy.Read.All'                            # Conditional Access -> entra_conditional_access_policies
    'Application.Read.All'                        # app registrations -> entra_app_registrations
    'RoleManagement.Read.Directory'              # directory role assignments -> entra_role_assignments
    'UserAuthenticationMethod.Read.All'          # auth methods -> entra_auth_methods
    'CustomSecAttributeAssignment.Read.All'      # custom security attribute assignments -> entra_custom_security_attributes
    'CustomSecAttributeDefinition.Read.All'      # custom security attribute definitions
    'Sites.Read.All'                             # SharePoint sites -> sharepoint_sites
    'InformationProtectionPolicy.Read.All'       # sensitivity labels -> m365_sensitivity_labels
)

# GATED — protected APIs (message bodies / call records). Only added with -IncludeComms,
# and only for the scoped-interaction collector (LP ADR-0022, dormant). Extra Microsoft
# approval is required for some of these.
$GatedCommsPermissions = @(
    'Mail.Read'
    'Chat.Read.All'
    'ChannelMessage.Read.All'
    'OnlineMeetings.Read.All'
    'CallRecords.Read.All'
)

$wanted = $ReadOnlyPermissions + ($(if ($IncludeComms) { $GatedCommsPermissions } else { @() }))

# ── 1. Connect as Global Admin of the target tenant ─────────────────────────────────────
$connectScopes = @('Application.ReadWrite.All', 'AppRoleAssignment.ReadWrite.All', 'Directory.Read.All')
Write-Host "Connecting to Microsoft Graph (sign in as a Global Admin of the target tenant)..." -ForegroundColor Cyan
if ($TenantId) { Connect-MgGraph -TenantId $TenantId -Scopes $connectScopes -NoWelcome }
else { Connect-MgGraph -Scopes $connectScopes -NoWelcome }

$context = Get-MgContext
if (-not $context) { throw 'Not connected to Microsoft Graph.' }
$resolvedTenantId = $context.TenantId
Write-Host "Connected to tenant $resolvedTenantId as $($context.Account)." -ForegroundColor Green

# ── 2. Resolve permission NAMES -> app-role ids from this tenant's Graph SP ──────────────
$graphSp = Get-MgServicePrincipal -Filter "appId eq '$GraphAppId'"
if (-not $graphSp) { throw "Microsoft Graph service principal not found in tenant $resolvedTenantId." }

$resolvedRoles = [System.Collections.Generic.List[object]]::new()
foreach ($name in $wanted) {
    $role = $graphSp.AppRoles | Where-Object { $_.Value -eq $name -and $_.AllowedMemberTypes -contains 'Application' }
    if (-not $role) {
        Write-Warning "Permission '$name' did not resolve to an application app-role in this tenant — SKIPPED."
        continue
    }
    $resolvedRoles.Add([pscustomobject]@{ Name = $name; Id = $role.Id })
}
if ($resolvedRoles.Count -eq 0) { throw 'No permissions resolved; aborting.' }
Write-Host "Resolved $($resolvedRoles.Count)/$($wanted.Count) permissions to app-role ids." -ForegroundColor Green

$requiredResourceAccess = @(
    @{
        ResourceAppId  = $GraphAppId
        ResourceAccess = @($resolvedRoles | ForEach-Object { @{ Id = $_.Id; Type = 'Role' } })
    }
)

# ── 3. Create (or reuse) the application ─────────────────────────────────────────────────
$escaped = $DisplayName.Replace("'", "''")
$app = Get-MgApplication -Filter "displayName eq '$escaped'" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($app) {
    Write-Host "Reusing existing app '$DisplayName' (appId $($app.AppId))." -ForegroundColor Yellow
    if ($PSCmdlet.ShouldProcess($DisplayName, 'Update requiredResourceAccess')) {
        Update-MgApplication -ApplicationId $app.Id -RequiredResourceAccess $requiredResourceAccess
    }
}
else {
    if ($PSCmdlet.ShouldProcess($DisplayName, 'Create application (read-only, single-tenant)')) {
        $app = New-MgApplication -DisplayName $DisplayName -SignInAudience 'AzureADMyOrg' `
            -RequiredResourceAccess $requiredResourceAccess `
            -Notes 'Imperion read-only pipeline access (per-client app model, ADR-0076/ADR-0103).'
        Write-Host "Created app '$DisplayName' (appId $($app.AppId))." -ForegroundColor Green
    }
}
if (-not $app) { Write-Warning '-WhatIf: app not created; nothing further to do.'; return }

# ── 4. Ensure the service principal exists ───────────────────────────────────────────────
$appSp = Get-MgServicePrincipal -Filter "appId eq '$($app.AppId)'" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $appSp -and $PSCmdlet.ShouldProcess($app.AppId, 'Create service principal')) {
    $appSp = New-MgServicePrincipal -AppId $app.AppId
    Write-Host "Created service principal (objectId $($appSp.Id))." -ForegroundColor Green
}

# ── 5. Grant admin consent (idempotent app-role assignments on the SP) ───────────────────
if ($appSp) {
    $existing = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $appSp.Id -All -ErrorAction SilentlyContinue
    foreach ($r in $resolvedRoles) {
        $already = $existing | Where-Object { $_.AppRoleId -eq $r.Id -and $_.ResourceId -eq $graphSp.Id }
        if ($already) { Write-Host "  consent present: $($r.Name)" -ForegroundColor DarkGray; continue }
        if ($PSCmdlet.ShouldProcess($r.Name, 'Grant admin consent (app-role assignment)')) {
            New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $appSp.Id `
                -PrincipalId $appSp.Id -ResourceId $graphSp.Id -AppRoleId $r.Id | Out-Null
            Write-Host "  consented: $($r.Name)" -ForegroundColor Green
        }
    }
}

# ── 6. Credential: client secret (default) or certificate upload ─────────────────────────
$secretValue = $null
$credExpires = $null
$authMethod = 'secret'
if ($UseCertificate) {
    $authMethod = 'cert'
    if (-not (Test-Path $CertificatePath)) { throw "Certificate not found: $CertificatePath" }
    $certBytes = [System.IO.File]::ReadAllBytes((Resolve-Path $CertificatePath))
    if ($PSCmdlet.ShouldProcess($app.AppId, 'Upload certificate (public key)')) {
        Update-MgApplication -ApplicationId $app.Id -KeyCredentials @(
            @{ Type = 'AsymmetricX509Cert'; Usage = 'Verify'; Key = $certBytes }
        )
        $thumb = ([System.Security.Cryptography.X509Certificates.X509Certificate2]::new($certBytes)).Thumbprint
        Write-Host "Uploaded certificate (thumbprint $thumb)." -ForegroundColor Green
        $credExpires = ([System.Security.Cryptography.X509Certificates.X509Certificate2]::new($certBytes)).NotAfter
    }
}
elseif ($PSCmdlet.ShouldProcess($app.AppId, 'Create client secret')) {
    $pw = Add-MgApplicationPassword -ApplicationId $app.Id -PasswordCredential @{
        DisplayName = 'Imperion pipeline read'
        EndDateTime = (Get-Date).AddMonths($SecretValidMonths)
    }
    $secretValue = $pw.SecretText
    $credExpires = $pw.EndDateTime
}

# ── 7. Output: what to seed into the Imperion GUI ────────────────────────────────────────
Write-Host ''
Write-Host '================ SEED THESE INTO THE IMPERION GUI (Settings -> Credentials) ================' -ForegroundColor Cyan
Write-Host ("  Provider     : graph (M365)            scope: client") -ForegroundColor White
Write-Host ("  Tenant Id    : {0}" -f $resolvedTenantId) -ForegroundColor White
Write-Host ("  Client Id    : {0}" -f $app.AppId) -ForegroundColor White
Write-Host ("  Auth method  : {0}" -f $authMethod) -ForegroundColor White
if ($secretValue) {
    Write-Host ("  Secret       : {0}" -f $secretValue) -ForegroundColor Yellow
    Write-Host  '  ^^^ SHOWN ONCE — copy it now. It is not stored on disk or in any log.' -ForegroundColor Yellow
}
Write-Host ("  Expires      : {0:yyyy-MM-dd}" -f $credExpires) -ForegroundColor White
Write-Host ("  Permissions  : {0}" -f ($resolvedRoles.Name -join ', ')) -ForegroundColor DarkGray
Write-Host '===========================================================================================' -ForegroundColor Cyan
Write-Host 'Next: map this tenant -> the client account in Settings -> Tenant mapping (account_tenant).' -ForegroundColor Cyan

# Return an object (without the secret) for scripted onboarding / logging.
[pscustomobject]@{
    TenantId    = $resolvedTenantId
    ClientId    = $app.AppId
    AuthMethod  = $authMethod
    Expires     = $credExpires
    Permissions = $resolvedRoles.Name
}
