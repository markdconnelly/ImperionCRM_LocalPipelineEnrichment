function Connect-ImperionSecretStore {
    <#
    .SYNOPSIS
        Unlock the local PowerShell SecretStore using the certificate (ADR-0002).
    .DESCRIPTION
        The vault password is stored as a CMS message encrypted to the machine certificate.
        This function decrypts it with the cert's private key (Unprotect-CmsMessage) and
        unlocks the SecretStore for the rest of the run. No password ever appears in a task
        argument or in plaintext on disk. Call once at task start.
    .PARAMETER CmsPasswordPath
        Path to the CMS-protected vault-password file (created by the bootstrap script).
    .PARAMETER VaultName
        SecretManagement vault name. Defaults to 'ImperionStore'.
    .EXAMPLE
        Connect-ImperionSecretStore -CmsPasswordPath C:\ProgramData\Imperion\vault.cms
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $CmsPasswordPath,
        [string] $VaultName = 'ImperionStore'
    )

    if (-not (Test-Path $CmsPasswordPath)) {
        throw "CMS vault-password file not found: $CmsPasswordPath. Run the unattended bootstrap first."
    }

    # Requires the certificate's private key to be present and ACL-readable by this identity.
    $plaintextPassword = Unprotect-CmsMessage -Path $CmsPasswordPath
    $securePassword = ConvertTo-SecureString -String $plaintextPassword -AsPlainText -Force
    $plaintextPassword = $null  # drop the plaintext copy promptly

    Unlock-SecretStore -Password $securePassword
    $script:ImperionSecretStoreVault = $VaultName
    Write-ImperionLog -Source 'secretstore' -Message "SecretStore '$VaultName' unlocked via certificate."
}
