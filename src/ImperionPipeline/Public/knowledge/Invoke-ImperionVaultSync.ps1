function Invoke-ImperionVaultSync {
    <#
    .SYNOPSIS
        SCAFFOLD / NOT-YET-WIRED. The "Later" LP arm of the Curated Vault local-sync
        (issue #306, ADR-0114 §8): promote the owner-zero rclone bisync job into a
        first-class LP collector that syncs every owner's local markdown folder against its
        per-owner Azure Blob container and feeds content hashes to the Curator's change
        detection.
    .DESCRIPTION
        The Curated Vault is a per-owner Azure Blob container (`vault-<owner>` on
        `imperioncrmstorageprd`) that the owner edits as a LOCAL markdown folder
        (Obsidian / VS Code). The bidirectional local-sync arm keeps the local folder
        in step with the blob container over HTTPS only — no SMB/445, no VPN, no on-prem
        server (the AFS/SMB approaches were rejected in ADR-0114).

        PHASING (issue #306):
          - NOW  (owner-zero = Mark): a standalone `rclone bisync` scheduled task on Mark's
            Win11 box, run under Mark's own Entra credentials. That arm is documented in
            docs/operations/curated-vault-local-sync.md and Mark runs it himself — the LIVE
            rclone run is Mark-gated and is NOT invoked from this cmdlet.
          - LATER (this cmdlet): once owner-zero round-trips reliably, promote the rclone job
            into this LP collector so all six owners' folders sync on the standing LP
            schedule, with content-hash reconciliation feeding `personal_vault_file.content_hash`
            (front-end migration 0169) so the Personal Curator can detect changed files
            without re-reading every blob.

        WHY THIS IS A SCAFFOLD AND NOT YET LIVE:
          - The owner-zero arm must be proven round-tripping in prod first (issue #306
            "Done when"): ship NOW, verify, then wire LATER — same ship-first/verify/cede
            discipline as the merge cutover (CLAUDE.md §6, ADR-0026).
          - Per-owner storage RBAC is owned by ImperionCRM #1176 (each owner gets
            `Storage Blob Data Contributor` on its own `vault-<owner>` container only); the
            LP service identity's own grant onto the vault containers is a NEW write
            capability and therefore an explicit, human-approved Azure grant (CLAUDE.md §2 /
            §8), not added here for convenience.
          - The owner roster + per-owner local-folder/container mapping is config that lands
            with the build issue, not invented from PowerShell.

        When wired, the intended shape mirrors the existing multi-target sync collectors
        (e.g. Invoke-ImperionUniFiDeviceSync): enumerate the owners, run `rclone bisync`
        per owner over one shared context, hash each synced file with
        Get-ImperionContentHash, and upsert `personal_vault_file.content_hash` so a re-run
        converges (idempotent, fail-closed per owner). Binaries land in the vault verbatim
        with a routing record into Distillation; rclone copies them byte-for-byte.

        Blob Event Grid is the event-driven upgrade path for change detection (ADR-0114 §8):
        once available, the Curator reacts to blob-write events instead of polling
        `content_hash`, and this scheduled reconciliation becomes the backstop rather than
        the primary signal.

        SECRET HANDLING: this cmdlet must never store, print, or pass credentials on a
        command line (CLAUDE.md §2/§8). The owner-zero arm uses Mark's `az login` /
        `AZURE_*` env auth; the LP arm will mint a short-lived token from the cert-backed
        service identity (the §6 pattern) — no vault SAS or account key is ever persisted.
    .PARAMETER Owner
        Optional owner key to limit the sync to a single owner (e.g. 'mark'). Omit to sweep
        every configured owner once wired. Owner-zero is 'mark'.
    .PARAMETER WhatIf
        Supported via ShouldProcess — this cmdlet writes (rclone bisync mutates both the
        local folder and the blob container, and it upserts `personal_vault_file`).
    .EXAMPLE
        Invoke-ImperionVaultSync -Owner mark -WhatIf
        # Shows what the owner-zero reconciliation WOULD do. The live rclone run remains
        # Mark-gated; see docs/operations/curated-vault-local-sync.md for the manual arm.
    .NOTES
        Status: SCAFFOLD — throws NotImplemented until the LATER phase is built. Tracked by
        issue #306; cross-repo parent epic ImperionCRM #1152 (Personal Knowledge Store);
        ADR-0114 §8 (vault substrate). Do NOT register a scheduled task against this cmdlet
        yet — it is not wired.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [string] $Owner
    )

    # The LP arm is intentionally inert until the owner-zero arm is verified in prod and the
    # build issue lands the owner roster + the LP service-identity vault grant (ImperionCRM
    # #1176). Surface that loudly rather than half-syncing against an unconfigured estate.
    $scope = if ($Owner) { "owner '$Owner'" } else { 'all owners' }
    Write-ImperionLog -Level Warn -Source 'vault' -Message (
        "Invoke-ImperionVaultSync is a scaffold (issue #306, LATER phase) and is not yet wired for $scope. " +
        'Owner-zero (Mark) runs the rclone bisync arm manually per docs/operations/curated-vault-local-sync.md.'
    )

    # ShouldProcess guard — this is a write path once wired (rclone bisync mutates the local
    # folder + blob container, and the reconciliation upserts personal_vault_file). Under
    # -WhatIf the scaffold reports the intended target and returns without throwing; a real
    # run still falls through to the NotImplemented guard below.
    if (-not $PSCmdlet.ShouldProcess("Curated Vault local-sync ($scope)", 'Reconcile vault <-> local folder')) {
        return
    }

    throw [System.NotImplementedException]::new(
        'Invoke-ImperionVaultSync is a scaffold for the Curated Vault LP-sync arm (issue #306, ADR-0114 §8). ' +
        'The owner-zero arm is run manually by Mark (Mark-gated rclone bisync); the LP collector is the ' +
        'fast-follow and is not yet implemented. See docs/operations/curated-vault-local-sync.md.'
    )
}
