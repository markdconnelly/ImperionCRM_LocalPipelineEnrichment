function Connect-ImperionSecretStore {
    <#
    .SYNOPSIS
        Unlock the local PowerShell SecretStore using the certificate (ADR-0002).
    .DESCRIPTION
        The vault password is stored as a CMS message encrypted to the machine certificate.
        This function decrypts it with the cert's private key (Unprotect-CmsMessage) and
        unlocks the SecretStore for the rest of the run. No password ever appears in a task
        argument or in plaintext on disk. Call once at task start.
    .PARAMETER Authentication
        'Password' (default) = the CMS-unlock model above. 'None' = the ADR-0002 DPAPI
        fallback: the store is bound to the task identity's profile and needs no password
        or CMS unlock (activated 2026-06-17 because the Entra cert lacks the Document
        Encryption EKU that Protect-CmsMessage requires). In 'None' mode CmsPasswordPath
        is ignored and the cert is used only for token minting, not vault unlock.
    .PARAMETER CmsPasswordPath
        Path to the CMS-protected vault-password file (created by the bootstrap script).
        Required only when -Authentication is 'Password'.
    .PARAMETER VaultName
        SecretManagement vault name. Defaults to 'ImperionStore'.
    .EXAMPLE
        Connect-ImperionSecretStore -CmsPasswordPath C:\ProgramData\Imperion\vault.cms
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'Unlock-SecretStore requires a SecureString. The password is CMS-decrypted in memory (cert private key) and the plaintext copy is cleared immediately; nothing is read from a plaintext literal or disk.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'CmsPasswordPath',
        Justification = 'CmsPasswordPath is a filesystem path to the CMS-encrypted blob, not a password value.')]
    [CmdletBinding()]
    param(
        [ValidateSet('Password', 'None')][string] $Authentication = 'Password',
        [string] $CmsPasswordPath,
        [string] $VaultName = 'ImperionStore'
    )

    $script:ImperionSecretStoreVault = $VaultName

    if ($Authentication -eq 'None') {
        # DPAPI / -Authentication None (ADR-0002 fallback, activated 2026-06-17): the store is
        # bound to the task identity's profile, so it needs no password or CMS unlock. Nothing
        # to do beyond recording the vault name; Get-Secret resolves for the bound account.
        Write-ImperionLog -Source 'secretstore' -Message "SecretStore '$VaultName' uses DPAPI (Authentication None); no unlock required."
        return
    }

    if (-not $CmsPasswordPath) {
        throw "Password-authenticated SecretStore requires -CmsPasswordPath (set CmsPasswordPath in pipeline.config.psd1, or use SecretStoreAuthentication = 'None')."
    }
    if (-not (Test-Path $CmsPasswordPath)) {
        throw "CMS vault-password file not found: $CmsPasswordPath. Run the unattended bootstrap first."
    }

    # Requires the certificate's private key to be present and ACL-readable by this identity.
    $plaintextPassword = Unprotect-CmsMessage -Path $CmsPasswordPath
    $securePassword = ConvertTo-SecureString -String $plaintextPassword -AsPlainText -Force
    $plaintextPassword = $null  # drop the plaintext copy promptly

    Unlock-SecretStore -Password $securePassword
    Write-ImperionLog -Source 'secretstore' -Message "SecretStore '$VaultName' unlocked via certificate."
}
