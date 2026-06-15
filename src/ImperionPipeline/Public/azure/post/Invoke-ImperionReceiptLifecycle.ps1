function Invoke-ImperionReceiptLifecycle {
    <#
    .SYNOPSIS
        Enforce the 90-day receipt-blob lifecycle: delete the storage-account copy of receipts
        whose Autotask custody is verified, GUARDED so an unverified receipt is never deleted.
    .DESCRIPTION
        The scheduled on-prem enforcer for the receipt durability handoff (front-end ADR-0083,
        migration 0089; issue #169). Once the backend has pushed a receipt to Autotask as an
        ExpenseItemAttachment and **verified it stored** (read-back), Autotask becomes the durable
        system-of-record and the private storage-account copy is redundant after 90 days. This
        cmdlet reclaims that storage.

        **The safety invariant (ADR-0083 §Receipts) is absolute:** a receipt is deleted ONLY when
        `verified_in_autotask = true`. An aged receipt that is NOT yet verified is **retained and
        surfaced as flagged** for follow-up — it is never silently deleted. The guard lives in the
        SQL `WHERE` (only verified rows are ever selected for deletion) AND is re-asserted per row
        in PowerShell before the blob DELETE, so a query change alone can never bypass it.

        Per eligible receipt (uploaded_at older than -RetentionDays, verified, not already deleted):
          1. delete the blob via Remove-ImperionStorageBlob (idempotent — a 404/already-gone is a
             no-op that still stamps blob_deleted_at, so a re-run converges);
          2. stamp `receipt_attachment.blob_deleted_at = now()` (the local-pipeline role holds
             SELECT + UPDATE on this table only — front-end migration 0089 GRANTs).

        Idempotent and resumable (CLAUDE.md §6): rows with blob_deleted_at already set are excluded,
        and an already-absent blob is treated as success. A failing receipt is isolated, logged, and
        retried next run — it never blocks the batch. **No PII / no receipt content / no filenames /
        no blob paths are logged** (CLAUDE.md §8) — only counts and opaque receipt ids. Requires
        Initialize-ImperionContext.

        Honours -WhatIf / -Confirm end to end (this DELETES data) — a dry run reports the eligible
        and flagged sets without touching a single blob or row.
    .PARAMETER RetentionDays
        Age threshold in days against uploaded_at. A receipt is eligible only once it is older than
        this AND verified-in-Autotask. Default 90 (ADR-0083).
    .PARAMETER Connection
        Optional open Npgsql connection to reuse; otherwise one is opened from config and disposed.
    .PARAMETER AccountName
        Storage account override passed through to Remove-ImperionStorageBlob (defaults to config).
    .PARAMETER Container
        Receipt container override passed through to Remove-ImperionStorageBlob (defaults to config).
    .OUTPUTS
        [pscustomobject] tally { scanned; deleted; alreadyGone; flaggedUnverified; failed }.
    .EXAMPLE
        Invoke-ImperionReceiptLifecycle
        Delete verified receipt blobs older than 90 days; flag any aged-but-unverified ones.
    .EXAMPLE
        Invoke-ImperionReceiptLifecycle -WhatIf
        Report what would be deleted/flagged without touching any blob or row (dry run).
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([pscustomobject])]
    param(
        [ValidateRange(1, 3650)][int] $RetentionDays = 90,
        $Connection,
        [string] $AccountName,
        [string] $Container
    )

    $started = Get-Date
    $ownConnection = -not $Connection
    if ($ownConnection) { $Connection = New-ImperionDbConnection }

    try {
        # GUARD, part 1 — the SQL only ever returns rows that are BOTH past retention AND
        # verified-in-Autotask AND not already deleted. The unverified-but-aged set is selected
        # separately purely to flag it (never to delete it). Parameterized age cutoff; no PII columns.
        $eligibleSql = @'
SELECT id, blob_path
  FROM receipt_attachment
 WHERE blob_deleted_at IS NULL
   AND verified_in_autotask = true
   AND uploaded_at < (now() - make_interval(days => @days))
 ORDER BY uploaded_at
'@
        $eligible = @(Invoke-ImperionDbQuery -Connection $Connection -Sql $eligibleSql -Parameters @{ days = $RetentionDays })

        # The retained / flagged set: aged past retention but NOT yet verified — surfaced, never deleted.
        $flaggedSql = @'
SELECT count(*) AS n
  FROM receipt_attachment
 WHERE blob_deleted_at IS NULL
   AND verified_in_autotask = false
   AND uploaded_at < (now() - make_interval(days => @days))
'@
        $flaggedRow = Invoke-ImperionDbQuery -Connection $Connection -Sql $flaggedSql -Parameters @{ days = $RetentionDays }
        $flaggedUnverified = [int]($flaggedRow | Select-Object -First 1 -ExpandProperty n)

        if ($flaggedUnverified -gt 0) {
            # Loud, count-only warning so the unverified backlog is visible for follow-up.
            Write-ImperionLog -Level Warn -Source 'expense' `
                -Message "Receipt lifecycle: $flaggedUnverified receipt(s) aged past $RetentionDays days but NOT verified-in-Autotask - RETAINED/flagged, not deleted." `
                -Data @{ flaggedUnverified = $flaggedUnverified; retentionDays = $RetentionDays }
        }

        $deleted = 0
        $alreadyGone = 0
        $failed = 0

        foreach ($receipt in $eligible) {
            try {
                # GUARD, part 2 — re-assert the verified-in-Autotask invariant per row before the
                # irreversible blob DELETE. The cutoff query already enforces it; this defence-in-depth
                # re-read means a future query change can never silently delete an unverified receipt.
                $verifyRow = Invoke-ImperionDbQuery -Connection $Connection `
                    -Sql 'SELECT verified_in_autotask, blob_deleted_at FROM receipt_attachment WHERE id = @id' `
                    -Parameters @{ id = $receipt.id } | Select-Object -First 1
                if (-not $verifyRow -or -not $verifyRow.verified_in_autotask -or $verifyRow.blob_deleted_at) {
                    continue
                }

                # ShouldProcess gates the irreversible delete (and the WhatIf dry run). Opaque id only.
                if (-not $PSCmdlet.ShouldProcess("receipt $($receipt.id)", "Delete storage blob + stamp blob_deleted_at (90-day lifecycle)")) {
                    continue
                }

                $blobParams = @{ BlobPath = $receipt.blob_path }
                if ($AccountName) { $blobParams.AccountName = $AccountName }
                if ($Container) { $blobParams.Container = $Container }
                # Remove-ImperionStorageBlob is idempotent: $true = deleted, $false = already absent.
                $didDelete = Remove-ImperionStorageBlob @blobParams

                # Stamp the lifecycle delete whether the blob was present or already gone — both mean
                # "the storage copy is no longer there", so the row converges on a single re-run.
                Invoke-ImperionDbNonQuery -Connection $Connection `
                    -Sql 'UPDATE receipt_attachment SET blob_deleted_at = now() WHERE id = @id AND blob_deleted_at IS NULL' `
                    -Parameters @{ id = $receipt.id } | Out-Null

                if ($didDelete) { $deleted++ } else { $alreadyGone++ }
            }
            catch {
                # One bad receipt never blocks the batch: log count-only and let the next run retry it.
                $failed++
                Write-ImperionLog -Level Error -Source 'expense' `
                    -Message "Receipt lifecycle: failed to delete blob for receipt $($receipt.id) - left intact, will retry next run." `
                    -Data @{ receiptId = "$($receipt.id)"; error = $_.Exception.Message }
            }
        }

        $tally = [pscustomobject]@{
            scanned           = @($eligible).Count
            deleted           = $deleted
            alreadyGone       = $alreadyGone
            flaggedUnverified = $flaggedUnverified
            failed            = $failed
        }

        Write-ImperionLog -Level Metric -Source 'expense' -Message 'Receipt 90-day lifecycle complete.' -Data @{
            scanned           = $tally.scanned
            deleted           = $tally.deleted
            alreadyGone       = $tally.alreadyGone
            flaggedUnverified = $tally.flaggedUnverified
            failed            = $tally.failed
            retentionDays     = $RetentionDays
            seconds           = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
        }

        return $tally
    }
    finally { if ($ownConnection) { $Connection.Dispose() } }
}
