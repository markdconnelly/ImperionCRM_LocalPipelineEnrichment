# ADR-0012: Local service account `.\svc-imperion` as the unattended run-as identity (workgroup host — no gMSA)

| Field | Value |
|---|---|
| **Status** | Accepted (2026-06-11, Mark's call) |
| **Issue** | #94 (epic #81) |
| **Amends** | ADR-0002 (certificate-rooted unattended execution — its "gMSA (preferred)" identity) |
| **Cross-references** | docs/deployment/unattended-bringup.md · docs/operations/scheduled-task-registry.md |

## Context

CLAUDE.md §2 and ADR-0002 prefer a **gMSA** as the scheduled-task identity. A gMSA
requires Active Directory; **MARKSWORKPC is a workgroup machine**, so a gMSA is
impossible (verified 2026-06-10 during the task-registration audit — zero Imperion
tasks existed, no gMSA). The documented fallback order was: dedicated local service
account, then (least preferred) running as Mark's interactive account.

## Decision

The nine scheduled tasks run as a **dedicated local account `.\svc-imperion`**:

1. **Account:** created by `build/New-ImperionServiceAccount.ps1` (elevated, run-once):
   password prompted (never an argument/log line), `PasswordNeverExpires`, granted
   **"Log on as a batch job"** (SeBatchLogonRight via secedit), optionally denied
   interactive logon. Mark custodies the password (password manager).
2. **Registration:** Task Scheduler cannot run a local account unattended without
   stored credentials, so `Register-ImperionTask` gains a **`-TaskCredential`**
   parameter set: local accounts register `-User/-Password` (stored by Task
   Scheduler); the gMSA `-TaskIdentity` path (principal, no stored password) remains
   for a future domain-joined host. The password never appears in the task action,
   logs, or process lists; a password change requires re-running
   `Register-ImperionTask`.
3. **Everything else from ADR-0002 binds to this account instead of a gMSA:** the
   machine cert's private-key ACL targets `.\svc-imperion` only; the SecretStore
   vault lives in *its* profile (`Initialize-ImperionUnattended` runs AS it); tasks
   run "whether user is logged on or not".

Rejected: running tasks as `markd` (interactive account owns crown-jewel cert +
vault; a compromised task = Mark's session; password rotation breaks all nine tasks
*and* his login).

## Consequences

- Unblocks the epic #81 bringup: account → cert ACL → SecretStore → chain test →
  one `Register-ImperionTask -TaskCredential` run registers all nine tasks.
- Stored task credentials are a known, accepted weakening vs a gMSA (Task Scheduler
  keeps the secret in the LSA store). Mitigations: batch-only logon, optional
  interactive-logon deny, least-privileged account, the cert remains the actual
  credential for everything off-box.
- If the host ever joins a domain, move to a gMSA (the `-TaskIdentity` path) and
  supersede this ADR.

## Security impact

Local-only identity change; no Azure/Graph grant is touched. The account holds no
rights beyond batch logon + the cert private-key read; everything off-box still
authenticates as the cert-backed SP (read-only by default, ADR-0002). Password
custody is Mark's; the repo and logs never contain it.
