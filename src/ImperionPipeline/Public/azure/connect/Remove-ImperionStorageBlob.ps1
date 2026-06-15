function Remove-ImperionStorageBlob {
    <#
    .SYNOPSIS
        Delete one blob from a private Azure Storage account via the cert-backed Entra SP (ADR-0002/§2).
    .DESCRIPTION
        Data-plane DELETE for the receipt 90-day lifecycle (ADR-0015 / front-end ADR-0083). Mints a
        short-lived Storage data-plane token via the certificate SP (the app holds the agreed
        **Azure Storage data-plane write** grant, CLAUDE.md §2 — the ONE write grant this needs) and
        issues an authenticated `DELETE` against the blob over TLS.

        **Idempotent by contract (CLAUDE.md §6):** a `404 Not Found` (blob already gone) is treated as
        success and returns `$false` (nothing deleted) rather than throwing — a re-run converges. A
        real `200/202` delete returns `$true`. Any other status fails loudly via the retry core.

        The blob path is the private storage-account key recorded in `receipt_attachment.blob_path`.
        Nothing about the receipt content is logged here (CLAUDE.md §8) — the caller logs counts only.
        Requires Initialize-ImperionContext.
    .PARAMETER AccountName
        Storage account name (e.g. 'imperionreceiptsprd'). Defaults to config Storage.AccountName.
    .PARAMETER Container
        Blob container holding the receipts. Defaults to config Storage.ReceiptContainer.
    .PARAMETER BlobPath
        The blob path/key within the container (receipt_attachment.blob_path).
    .PARAMETER TenantId
        Tenant to authenticate against; defaults to the partner tenant (the MSP's own storage).
    .PARAMETER ApiVersion
        Azure Blob REST api-version. Default 2023-11-03.
    .OUTPUTS
        [bool] $true if a blob was deleted, $false if it was already absent (idempotent no-op).
    .EXAMPLE
        Remove-ImperionStorageBlob -BlobPath 'receipts/2026/03/abc.pdf'
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [string] $AccountName,
        [string] $Container,
        [Parameter(Mandatory)][string] $BlobPath,
        [string] $TenantId,
        [string] $ApiVersion = '2023-11-03'
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }
    if (-not $AccountName -and ($cfg -is [System.Collections.IDictionary]) -and $cfg.Contains('Storage')) {
        $AccountName = $cfg['Storage'].AccountName
    }
    if (-not $Container -and ($cfg -is [System.Collections.IDictionary]) -and $cfg.Contains('Storage')) {
        $Container = $cfg['Storage'].ReceiptContainer
    }
    if (-not $AccountName) { throw 'No storage account: pass -AccountName or set Storage.AccountName in pipeline.config.psd1.' }
    if (-not $Container) { throw 'No receipt container: pass -Container or set Storage.ReceiptContainer in pipeline.config.psd1.' }

    # The blob path may already include the container prefix or a leading slash — normalize to the
    # bare blob key so we never double up the container segment in the URL.
    $blobKey = $BlobPath.TrimStart('/')
    if ($blobKey.StartsWith("$Container/")) { $blobKey = $blobKey.Substring($Container.Length + 1) }
    $encodedKey = ($blobKey -split '/' | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'

    $uri = 'https://{0}.blob.core.windows.net/{1}/{2}' -f $AccountName, $Container, $encodedKey

    if (-not $PSCmdlet.ShouldProcess("blob $Container/$blobKey", 'Delete receipt blob (90-day lifecycle)')) {
        return $false
    }

    $token = Get-ImperionStorageToken -TenantId $TenantId
    $headers = @{ Authorization = "Bearer $token"; 'x-ms-version' = $ApiVersion }

    # Treat 404 (already deleted) as an idempotent no-op rather than a hard failure.
    $resp = Invoke-ImperionHttp -Uri $uri -Headers $headers -Method 'DELETE'
    if ($resp.Status -eq 404) { return $false }
    if ($resp.Status -ge 200 -and $resp.Status -lt 300) { return $true }
    throw "HTTP $($resp.Status) deleting blob $Container/$blobKey from account $AccountName."
}
