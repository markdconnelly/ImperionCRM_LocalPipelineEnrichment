# Least-privilege grants (as-built)

The cert-backed Entra app is **read-only by default** across Azure and Microsoft 365
(pipeline ADR-0018 — client M365 access is the per-client onboarding app; GDAP is
scrapped). Record the exact as-built grant set here and treat any widening as a security
event requiring human approval.

## Microsoft 365 / Entra (read-only)
- **Imperion's own tenant:** `Application.Read.All` *or* `Directory.Read.All` (Graph
  application permission) for the service-principal inventory; additional read scopes per
  source.
- **Client tenants:** via the **per-client, admin-consented onboarding app** (pipeline
  ADR-0018) — the **minimal Graph application permissions** that satisfy read needs, never
  broad admin grants for convenience. Document the exact onboarding-app permission grants
  per source in `integrations/`.

## Azure (read-only by default + three write grants)
| Scope | Role | Why |
| --- | --- | --- |
| Management groups / subscriptions | **`Reader`** | inventory + Sentinel reads |
| Azure Storage (the pipeline's account) | data-plane write | staging/landing artifacts |
| Shared PostgreSQL | Entra role, **table-scoped** | write bronze/silver/gold + vectors |
| Key Vault | **`Key Vault Secrets User`** | read secrets/refs |

## Rules
- **No write anywhere else.** A net-new write capability (e.g. the IT Glue documentation
  write path, or a new Azure data-plane role) is an **explicit, documented, human-approved**
  grant — never added to make a task easier.
- **Access is per-client onboarding-app credentials — fail closed.** Never operate against
  a tenant with no current consent / credential pair.
- Keep this doc current; it is the audit reference for the grant set.
