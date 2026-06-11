# ADR-0003: Short-lived Entra token for Postgres (no stored DB password)

| Field | Value |
|---|---|
| **Repo** | local-pipeline |
| **Status** | Accepted |
| **Date** | 2026-06-08 |
| **Deciders** | Mark (human), Claude Code |
| **Cross-references** | — |

## Problem

The home server writes to the shared Azure PostgreSQL. An earlier draft stored a Postgres
username/password in the SecretStore. Mark prefers a **short-lived** credential. The
siblings already authenticate to Postgres with Entra tokens (no stored password).

## Options considered

None recorded in the original ADR.

## Decision

**No stored DB password.** At task start the cert-backed Entra service principal mints a
**short-lived AAD access token** for Azure Database for PostgreSQL
(resource `https://ossrdbms-aad.database.windows.net/.default`). PowerShell connects with
that token as the password, username = the SP's Entra principal name, over TLS
(`sslmode=require`). The token lives only for the run.

Requires:
- A **Postgres Entra role** for the SP (`pgaadauth_create_principal`) with GRANTs scoped to
  **exactly the tables this repo touches** (the bronze/silver/gold + vector tables).
- An Azure PostgreSQL **firewall rule** for the home WAN IP (see
  [azure-postgres-firewall.md](../operations/azure-postgres-firewall.md)).

## Consequences

### Security impact

- **Security impact:** no long-lived DB secret anywhere; least-privilege DB role; token
  expiry limits replay. Matches the system's token-only posture.

### Cost impact

- **Cost impact:** none.

### Operational impact

- **Operational impact:** a **dynamic residential IP** will break unattended runs — needs a
  static IP, VPN, or an IP-refresh task. Token must be refreshed for long-running jobs.

## Future considerations

- **Future considerations:** if the home node moves into a VNet/private endpoint later, the
  firewall rule is replaced by private networking.

## Cross-references

This repo `CLAUDE.md §6`; `ImperionCRM_Pipeline` MI-based Postgres auth (sibling pattern).
