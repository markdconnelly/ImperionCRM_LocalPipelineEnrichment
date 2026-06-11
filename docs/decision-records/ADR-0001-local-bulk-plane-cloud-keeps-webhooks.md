# ADR-0001: Local PowerShell pipeline as the bulk-compute plane; cloud Pipeline keeps webhooks

| Field | Value |
|---|---|
| **Repo** | local-pipeline |
| **Status** | Accepted |
| **Date** | 2026-06-08 |
| **Deciders** | Mark (human), Claude Code |
| **Cross-references** | — |

## Problem

Heavy data-pipeline processing — bulk source polling, the bronze→silver→gold transforms,
and (above all) embedding generation — was choking the live website and would starve the
shared Azure App Service Plan that also runs interactive requests and the agent loop. These
workloads are high-volume, long-running, retry-heavy, and bursty. Mark has an always-on
home server that can run them on a schedule with no per-second compute bill and full local
read access to the shared database.

## Options considered

1. **Move everything local; retire the cloud Pipeline.** Simplest mental model, but a home
   server behind NAT/dynamic IP cannot reliably receive signed inbound webhooks (Autotask
   ticket webhooks, Microsoft Graph change-notifications), and loses sub-minute latency.
2. **Local heavy-compute only; cloud keeps all polling.** Smallest change, but leaves the
   bulk polling load on Azure — the thing that was choking the system.
3. **Coexist (chosen).** Local owns all scheduled/bulk polling, the transforms, and all
   vectorization; the cloud Pipeline keeps **only** the internet-facing webhook receivers
   and sub-minute event work.

## Decision

**Coexist.** Two pipeline planes with a hard boundary: *anything that must receive inbound
internet traffic stays in the cloud Pipeline; everything scheduled or compute-heavy runs
on the local PowerShell node.* If a task needs both, split it — the cloud receiver writes a
landing row/queue message, the local task picks it up on its cadence.

## Consequences

### Security impact

- **Security impact:** the local node has **no inbound network surface** (outbound-only),
  shrinking its attack surface. The cloud webhook receivers keep their signature validation.

### Cost impact

- **Cost impact:** bulk + embedding compute moves off metered Azure compute onto owned
  hardware; cloud footprint shrinks to thin webhook receivers.

### Operational impact

- **Operational impact:** two deploy targets (Azure Functions + Windows Scheduled Tasks);
  a clear ownership line per workload. Local node availability now matters for freshness.

## Future considerations

- **Future considerations:** if the home node proves unreliable, individual jobs can be
  lifted back to cloud Functions without schema change (same DB, same medallion contract).

## Cross-references

`ImperionCRM_Pipeline/CLAUDE.md §1–§4` (the cloud plane it complements); this repo
`CLAUDE.md §1`.
