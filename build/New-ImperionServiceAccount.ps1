#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Create the dedicated local service account that runs the Imperion scheduled tasks (ADR-0012).
.DESCRIPTION
    Elevated, interactive, run-once helper for a WORKGROUP host (no gMSA possible):
      1. creates the local account (password prompted — never an argument, never logged),
      2. grants it "Log on as a batch job" (SeBatchLogonRight via secedit),
      3. optionally denies interactive logon (recommended for a pure service identity).

    It does NOT touch the certificate or the SecretStore — those are the runbook's
    manual steps (docs/deployment/unattended-bringup.md): ACL the cert private key to
    this account, then run Initialize-ImperionUnattended AS this account, then
    Register-ImperionTask -TaskCredential (Get-Credential '.\svc-imperion').
.PARAMETER Name
    Local account name. Default 'svc-imperion'.
.PARAMETER DenyInteractiveLogon
    Also grant SeDenyInteractiveLogonRight so the account can never log on at the
    console — batch (scheduled task) use only.
.EXAMPLE
    .\build\New-ImperionServiceAccount.ps1 -DenyInteractiveLogon
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $Name = 'svc-imperion',
    [switch] $DenyInteractiveLogon
)

$ErrorActionPreference = 'Stop'

$existing = Get-LocalUser -Name $Name -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Local account '$Name' already exists - skipping creation (rights are still applied)."
}
elseif ($PSCmdlet.ShouldProcess($Name, 'Create local service account')) {
    $password = Read-Host -AsSecureString -Prompt "Password for new local account '$Name' (store it in your password manager - Register-ImperionTask will prompt for it)"
    New-LocalUser -Name $Name -Password $password -PasswordNeverExpires -AccountNeverExpires `
        -Description 'Imperion pipeline scheduled-task identity (ADR-0012). Batch logon only.' | Out-Null
    Write-Host "Created local account '$Name'."
}

# ── Logon rights via secedit (no native cmdlet exists) ──────────────────────────
$sid = (Get-LocalUser -Name $Name).SID.Value

function Grant-ImperionLogonRight {
    param([string] $RightName, [string] $AccountSid)

    $exportPath = Join-Path $env:TEMP "imperion-secpol-$([guid]::NewGuid().Guid).inf"
    $importPath = Join-Path $env:TEMP "imperion-secpol-$([guid]::NewGuid().Guid).inf"
    try {
        secedit /export /cfg $exportPath /areas USER_RIGHTS | Out-Null
        $current = (Select-String -Path $exportPath -Pattern "^$RightName\s*=").Line

        if ($current -and $current -match [regex]::Escape($AccountSid)) {
            Write-Host "$RightName already includes $AccountSid - nothing to do."
            return
        }
        $newLine = if ($current) { "$current,*$AccountSid" } else { "$RightName = *$AccountSid" }

        @(
            '[Unicode]', 'Unicode=yes',
            '[Version]', 'signature="$CHICAGO$"', 'Revision=1',
            '[Privilege Rights]', $newLine
        ) | Set-Content -Path $importPath -Encoding Unicode
        secedit /configure /db "$env:windir\security\local.sdb" /cfg $importPath /areas USER_RIGHTS | Out-Null
        Write-Host "Granted $RightName to $AccountSid."
    }
    finally {
        Remove-Item $exportPath, $importPath -Force -ErrorAction SilentlyContinue
    }
}

if ($PSCmdlet.ShouldProcess($Name, 'Grant "Log on as a batch job"')) {
    Grant-ImperionLogonRight -RightName 'SeBatchLogonRight' -AccountSid $sid
}
if ($DenyInteractiveLogon -and $PSCmdlet.ShouldProcess($Name, 'Deny interactive logon')) {
    Grant-ImperionLogonRight -RightName 'SeDenyInteractiveLogonRight' -AccountSid $sid
}

Write-Host @"

Next (docs/deployment/unattended-bringup.md):
  1. Cert into Cert:\LocalMachine\My + private-key read ACL'd to '$Name' only.
  2. AS '$Name':  Initialize-ImperionUnattended -CertThumbprint <thumbprint> -TaskIdentity '.\$Name'
  3. Set-Secret the source API keys; pwsh -File build\Test-ImperionUnattendedChain.ps1 (all PASS).
  4. Elevated:    Register-ImperionTask -TaskCredential (Get-Credential '.\$Name')
"@
