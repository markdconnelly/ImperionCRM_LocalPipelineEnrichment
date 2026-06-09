function Initialize-ImperionUnattended {
    <#
    .SYNOPSIS
        One-time operator setup for unattended execution: SecretStore + CMS-protected password + cert key ACL (ADR-0002).
    .DESCRIPTION
        Registers the SecretStore vault, sets a random vault password configured for
        unattended (password) access, encrypts that password to the certificate as a CMS
        message so scheduled tasks can unlock it with the cert's private key, and grants the
        task identity read access to the cert's private key. Run once, interactively, as
        administrator. Re-runnable for rotation.
    .PARAMETER CertThumbprint
        Thumbprint of the certificate in Cert:\LocalMachine\My.
    .PARAMETER VaultName
        SecretStore vault name. Default 'ImperionStore'.
    .PARAMETER CmsPasswordPath
        Where to write the CMS-protected vault password.
    .PARAMETER TaskIdentity
        The gMSA/service account that runs the scheduled tasks (e.g. 'DOMAIN\svc-imperion$').
    .EXAMPLE
        Initialize-ImperionUnattended -CertThumbprint ABC123… -TaskIdentity 'CORP\svc-imperion$'
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'The vault password is generated in-process from a CSPRNG and must be passed to Set-SecretStoreConfiguration as a SecureString; it is never read from a plaintext literal or disk and is cleared after use.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'CmsPasswordPath',
        Justification = 'CmsPasswordPath is a filesystem output path for the CMS-encrypted blob, not a password value.')]
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string] $CertThumbprint,
        [string] $VaultName = 'ImperionStore',
        [string] $CmsPasswordPath = 'C:\ProgramData\Imperion\vault.cms',
        [string] $TaskIdentity
    )

    $cert = Get-Item -Path "Cert:\LocalMachine\My\$CertThumbprint" -ErrorAction Stop
    Write-Host "Using certificate: $($cert.Subject) [$CertThumbprint]"

    if (-not (Get-SecretVault -Name $VaultName -ErrorAction SilentlyContinue)) {
        Register-SecretVault -Name $VaultName -ModuleName Microsoft.PowerShell.SecretStore -DefaultVault
    }

    $bytes = [byte[]]::new(48)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    $vaultPassword = [Convert]::ToBase64String($bytes)
    $secure = ConvertTo-SecureString $vaultPassword -AsPlainText -Force

    if ($PSCmdlet.ShouldProcess($VaultName, 'Configure SecretStore for unattended access')) {
        Set-SecretStoreConfiguration -Authentication Password -Interaction None -Password $secure -Confirm:$false
    }

    $dir = Split-Path -Parent $CmsPasswordPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    if ($PSCmdlet.ShouldProcess($CmsPasswordPath, 'Write CMS-protected vault password')) {
        Protect-CmsMessage -To $cert -Content $vaultPassword -OutFile $CmsPasswordPath
        Write-Host "Wrote CMS-protected vault password to $CmsPasswordPath"
    }
    $vaultPassword = $null

    if ($TaskIdentity) {
        $keyName = $null
        try { $keyName = ([System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)).Key.UniqueName }
        catch { Write-Verbose "Could not resolve the private-key unique name automatically: $($_.Exception.Message)" }
        $machineKeyDir = "$env:ProgramData\Microsoft\Crypto\Keys"
        $keyFile = Get-ChildItem -Path $machineKeyDir -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $keyName } | Select-Object -First 1
        if ($keyFile -and $PSCmdlet.ShouldProcess($TaskIdentity, "Grant read on private key $($keyFile.Name)")) {
            $acl = Get-Acl $keyFile.FullName
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($TaskIdentity, 'Read', 'Allow')
            $acl.AddAccessRule($rule)
            Set-Acl -Path $keyFile.FullName -AclObject $acl
            Write-Host "Granted $TaskIdentity read on the certificate private key."
        }
        else {
            Write-Warning "Could not resolve the private-key file automatically. Grant $TaskIdentity read manually (certlm.msc -> Manage Private Keys)."
        }
    }

    Write-Host "`nBootstrap complete. Next: add secrets with Set-Secret -Vault $VaultName, then Register-ImperionTask."
}
