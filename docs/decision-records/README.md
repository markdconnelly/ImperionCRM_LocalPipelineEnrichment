# Decision Records

_ImperionCRM_LocalPipelineEnrichment — `docs/decision-records`_

ADRs for every significant decision in this repo, written in the **unified Imperion ADR
format**: a metadata table (Repo `local-pipeline` / Status / Date / Cross-references, plus
Supersedes / Superseded-by / Amends / Amended-by rows where they apply) followed by
`Problem → Context → Options considered → Decision → Consequences (Security / Cost /
Operational impact) → Future considerations → Cross-references`. See
[_template.md](_template.md).

**ADR numbers are per-repo, not global** — the frontend and pipeline repos also have an
ADR-0001+, and they are different decisions. Always qualify a cross-repo reference with
the repo name ("frontend ADR-0043", "backend ADR-0035", "pipeline ADR-0011"); same-repo
references stay plain ("ADR-0002"). Never renumber or rename ADR files.

> Part of the system-wide `/docs` standard (front-end `CLAUDE.md` §8). See [../../CLAUDE.md](../../CLAUDE.md).

## Index

| ID | Title | Status | Date | Decision |
| --- | --- | --- | --- | --- |
| [ADR-0001](ADR-0001-local-bulk-plane-cloud-keeps-webhooks.md) | Local PowerShell pipeline as the bulk-compute plane; cloud Pipeline keeps webhooks | Accepted (completed by pipeline ADR-0011) | 2026-06-08 | Two pipeline planes coexist: the local node owns all scheduled/bulk polling, transforms, and vectorization; the cloud Pipeline keeps only inbound webhook receivers and sub-minute event work. |
| [ADR-0002](ADR-0002-certificate-rooted-unattended-execution.md) | Certificate-rooted unattended execution + read-only-by-default grant | Accepted | 2026-06-08 | One non-exportable machine certificate unlocks the SecretStore (CMS) and is the Entra app credential; grants are read-only by default with explicit writes only to Storage, Postgres, and Key Vault. |
| [ADR-0003](ADR-0003-short-lived-entra-token-postgres.md) | Short-lived Entra token for Postgres (no stored DB password) | Accepted | 2026-06-08 | The cert-backed service principal mints a short-lived AAD token for Azure PostgreSQL per run, over TLS, with a table-scoped Entra role — no DB password is ever stored. |
| [ADR-0004](ADR-0004-vectorization-local-orchestration.md) | Vectorization: local orchestration, pinned pluggable embedding provider | Accepted (amended by ADR-0009) | 2026-06-08 | Embedding orchestration (chunking, dedup, batching, cost accounting, pgvector upsert) runs locally with one pinned model + dimension system-wide; provider was pluggable until ADR-0009 retired that framing. |
| [ADR-0005](ADR-0005-source-catalog-and-table-naming.md) | Source bronze catalog + table-naming reconciliation | Proposed (needs front-end migration sign-off) | 2026-06-08 | Adopt the sibling `{source}_{entity}` physical-table convention; new entities need front-end migrations first; loaders fail loudly on missing tables; `website_*` keeps highest merge precedence. |
| [ADR-0006](ADR-0006-itglue-documentation-relationship-hub.md) | IT Glue as a documentation + relationship hub in the ingestion path | Accepted | 2026-06-08 | Flatten each source to one flat PSObject table that is both documented (and related) in IT Glue and imported as-is into Postgres bronze, with a polymorphic edge table for IT Glue relationships. |
| [ADR-0007](ADR-0007-installed-powershell-module.md) | Package as an installed PowerShell module (not a folder of scripts) | Accepted | 2026-06-08 | Ship the versioned `ImperionPipeline` module with exported cmdlets and `Initialize-ImperionContext`; machine config lives in `%ProgramData%\Imperion\`, outside the module. |
| [ADR-0008](ADR-0008-golden-states-and-drift.md) | Golden states + drift detection for security-posture policies | Accepted | 2026-06-08 | Each security-posture policy type keeps an observed table plus a human-promoted golden baseline; `Get-ImperionPolicyDrift` classifies compliant / drift / ungoverned / missing by hash comparison. |
| [ADR-0009](ADR-0009-settled-embedding-stack-voyage-direct.md) | **The embedding stack is settled: Voyage direct, pinned, built** | Accepted | 2026-06-09 | Call Voyage `voyage-3-large` @ 1024 directly — no provider router — with every constant pinned in `Get-ImperionVectorContract`; chunk-hash idempotency means unchanged content is never re-billed. |
| [ADR-0010](ADR-0010-posture-silver-bulk-merge.md) | Posture silver bulk merge — the scheduled twin of the cloud's on-demand refresh | Accepted | 2026-06-11 | `Invoke-ImperionPostureMerge` (daily 03:20) classifies every tenant's policies into posture_policy and rolls up tenant_posture, one transaction per tenant, with the classification CASE parity-pinned across three implementations. |
| [ADR-0011](ADR-0011-quarterly-posture-snapshots.md) | Quarterly Imperion Secure Score snapshots — daily-gated calendar quarters, parity-pinned score math | Accepted | 2026-06-11 | `Invoke-ImperionPostureSnapshot` (daily 03:40, self-gated to one scheduled snapshot per account per calendar quarter) INSERTs immutable snapshot + pillar rows using `Get-ImperionSecureScore`, the PowerShell twin of the frontend's `imperion-score.ts`. |
| [ADR-0012](ADR-0012-local-service-account-identity.md) | Local service account `.\svc-imperion` as the unattended run-as identity (workgroup host — no gMSA) | Accepted | 2026-06-11 | gMSA impossible without AD, so the nine tasks run as a dedicated local account created by `New-ImperionServiceAccount.ps1` and registered with stored credentials via `Register-ImperionTask -TaskCredential`. |
