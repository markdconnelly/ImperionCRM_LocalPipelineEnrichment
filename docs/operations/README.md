# Operations

_ImperionCRM_LocalPipelineEnrichment — `docs/operations`_

Scheduled-task registry, change-detection strategy, certificate rotation, secret rotation, the Azure PostgreSQL firewall/IP runbook, and the Curated Vault local-sync runbook.

> Part of the system-wide `/docs` standard (front-end `CLAUDE.md` §8). See [../../CLAUDE.md](../../CLAUDE.md).

## Runbooks

- [`curated-vault-local-sync.md`](curated-vault-local-sync.md) — rclone `bisync` keeps a per-owner Curated Vault blob container in sync with the owner's local markdown folder over HTTPS (issue #306, ADR-0114 §8). Owner-zero (Mark) runs the manual arm; the LP collector arm (`Invoke-ImperionVaultSync`) is the scaffolded fast-follow.

