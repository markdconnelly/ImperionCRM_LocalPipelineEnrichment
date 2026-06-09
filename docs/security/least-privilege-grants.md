# Least-privilege grants (as-built)

The cert-backed Entra app is **read-only by default** across Azure and Microsoft 365
(ADR-0002). Record the exact as-built grant set here and treat any widening as a security
event requiring human approval.

## Microsoft 365 / Entra (read-only)
- **Partner tenant:** `Application.Read.All` *or* `Directory.Read.All` (Graph application
  permission) for the service-principal inventory; additional read scopes per source.
- **Customer tenants:** via **GDAP**, the **minimal delegated roles** that satisfy read
  needs — never broad admin roles for convenience. Document the exact GDAP roles per source
  in `integrations/`.

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
- **GDAP is time-bound — fail closed.** Never operate against an expired relationship.
- Keep this doc current; it is the audit reference for the grant set.
