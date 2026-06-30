# Security-posture bronze (guide)

Beyond CRM/support/finance, the module ingests the **Microsoft security estate** read-only and
maintains an approved **golden state** per policy type so it can flag **drift**. This is the
"are these tenants configured the way we agreed?" surface, fed to the agent as gold posture
objects.

> **Deeper references:** the golden-state / drift mechanics are
> [`database/golden-states-and-drift.md`](database/golden-states-and-drift.md); per-source
> auth/fields are in [`integrations/`](integrations/) (`secure-score.md`,
> `security-posture-policies.md`, `security-incidents.md`, `purview-compliance.md`). ADRs:
> **ADR-0008** (golden states + drift) · **ADR-0010** (silver merge) · **ADR-0011** (quarterly
> snapshots) · **ADR-0019** (incidents + Purview).

## The posture pipeline

```mermaid
flowchart TB
    subgraph READ["Read-only Graph / ARM (cert SP + per-client onboarding app)"]
      direction TB
      SS["Invoke-ImperionSecureScoreSync"]
      POL["Invoke-ImperionPolicySync (CA · Intune · device-config · Autopilot · Defender)"]
      SP["Invoke-ImperionServicePrincipalSync"]
      INV["Invoke-ImperionAzureInventorySync (+ Sentinel)"]
      INC["Get-ImperionSecurityIncident -> Set-ImperionSecurityIncidentToBronze"]
      PUR["Invoke-ImperionPurviewComplianceSync"]
    end

    READ --> BRONZE
    subgraph BRONZE["Bronze (per type)"]
      direction TB
      B1["secure_scores · secure_score_control_profiles"]
      B2["*_policies (CA / Intune / device-config / Autopilot / Defender XDR)"]
      B3["m365_incidents / m365_alerts / m365_evidence"]
      B4["purview_compliance_policies"]
    end

    GOLDEN[("*_golden baselines<br/>(Set-ImperionPolicyGoldenState, human-gated)")]
    BRONZE --> DRIFT["Get-ImperionPolicyDrift<br/>compliant / drift / ungoverned / missing"]
    GOLDEN --> DRIFT

    BRONZE --> MERGE["Invoke-ImperionPostureMerge (silver: posture_policy + tenant_posture)"]
    MERGE --> SNAP["Invoke-ImperionPostureSnapshot (immutable quarterly Imperion Secure Score)"]
    DRIFT --> KNOW["Get-ImperionKnowledgePosture -> knowledge_object ('posture')"]
    SNAP --> KNOW
    KNOW --> VEC[("knowledge_embedding (agent reads)")]
```

## Per-client fan-out (ADR-0126 / #381)

Posture is **per-client, not Imperion-only**. `Invoke-ImperionPolicySync` (and the estate
posture reads alongside it) fan out over **every mapped client tenant** via
`Invoke-ImperionM365EstateSweep` — the same registry-driven sweep the directory collectors use
(`account_tenant` ⨝ an active `m365` `connection`, the #358 estate fan-out, ADR-0030). Each
tenant is reached read-only through the per-client onboarding app (§3) and is **fail-isolated**:
a tenant that 403s or lacks consent logs a Warn and is skipped without aborting the rest.
`-TenantId` pins a single tenant (#359). A GUI-mapped, credentialed tenant therefore joins the
posture sweep on the next run with no host edit (#379/#381).

## Policy types & golden states (ADR-0008)

Each policy type keeps an approved **golden state** (the baseline we promote a known-good policy
to). `Get-ImperionPolicyDrift` compares live bronze vs golden and verdicts each:
**compliant / drift / ungoverned / missing**.

**Drift-loop robustness (#409/#412):** a golden table whose shape does not match the drift
contract (e.g. `purview_compliance_golden` created with the bronze `content_hash` instead of the
contract's `golden_hash`) makes `Get-ImperionPolicyDrift` **skip that one policy type** with a
structured Warn and keep evaluating the rest — it no longer aborts the whole posture composer
(which would take the nightly knowledge sync down with it). The query runs in autocommit, so a
failed type leaves the connection usable; the proper repair is the front-end schema fix that
gives the golden table its `golden_hash` column.

| Area | What | Observed table(s) | Golden state |
| --- | --- | --- | --- |
| **Secure Score** | overall snapshots + control attributes | `secure_scores`, `secure_score_control_profiles` | — |
| **Conditional Access** | CA policies | `entra_conditional_access_policies` | `conditional_access_policies_golden` |
| **Intune security** | settings-catalog / endpoint security | `intune_security_policies` | `intune_security_policies_golden` |
| **Device configuration** | device config profiles | `device_configuration_policies` | `device_configuration_policies_golden` |
| **Autopilot** | deployment profiles | `autopilot_policies` | `autopilot_policies_golden` |
| **Defender XDR** | endpoint-security (AV/EDR/FW/ASR) | `defender_xdr_security_policies` | `defender_xdr_security_policies_golden` |

`Set-ImperionPolicyGoldenState` promotes a current policy to baseline — **human-gated**.

## Silver merge & quarterly snapshots

- **`Invoke-ImperionPostureMerge`** (daily 03:20, after Secure Score + PolicySync) classifies
  the night's fresh bronze into silver `posture_policy` and rolls it up to `tenant_posture`,
  including unmapped tenants (ADR-0010).
- **`Invoke-ImperionPostureSnapshot`** (daily 03:40, self-gates to calendar quarters) writes an
  **immutable** `posture_snapshot` (+ pillar) per mapped account — the **Imperion Secure Score**,
  Score Model v1 parity-pinned to the front-end `imperion-score.ts` (ADR-0011). On-demand / QBR
  triggers bypass the quarter gate.

## Incidents, Purview, and retention (ADR-0019)

- **Security incidents** (`Get-ImperionSecurityIncident` → `Set-ImperionSecurityIncidentToBronze`,
  hourly) — the incident → alerts → evidence fidelity payload → `m365_incidents` / `m365_alerts`
  / `m365_evidence`, carrying `autotask_ticket_ref` **raw** (format **confirm-before-live** before
  the MS↔Autotask silver stitch). Read-only onboarding-app Graph. **DORMANT until creds** (#102).
- **Purview compliance** (`Invoke-ImperionPurviewComplianceSync`, daily) — compliance **posture
  only, NO alerts** → `purview_compliance_policies` + `_golden` drift via the existing engine.
  Held out of the posture silver merge until the FE widens the `policy_family` CHECK.
- **180-day retention sweep** (`Invoke-ImperionSecurityRetentionSweep`, daily) — prunes
  `m365_incidents` / `m365_alerts` / `m365_evidence` **ONLY** (Autotask is the durable system of
  record). Leaf-first, idempotent, `-WhatIf`-aware, count-only logging; first live run is gated.

## Other security sources

Dark Web ID (credential compromises), Telivy (assessment reports), EasyDMARC (domain DMARC/SPF/
DKIM/BIMI posture), and the DNS golden/drift planes (ADR-0063) all land here too — see the
[collector inventory](collector-inventory.md).

## Posture data → gold

`Get-ImperionKnowledgePosture` composes **one `knowledge_object` per tenant** — latest Secure
Score + per-type policy drift counts and **named gaps** via `Get-ImperionPolicyDrift` — which the
vectorizer embeds so the agent can reason over each tenant's security stance. No per-policy raw
detail or PII enters gold.

## Posture & secrets

All posture reads are **read-only** (broad `Reader` on Azure + the read-only onboarding app on
365). Credential compromise detail (Dark Web ID) is carried as **facts**, never plaintext
credentials. **Never commit secrets.** Provenance and lawful-basis stamping apply per the system
posture (referenced, not restated, from `unified-security-standard.md`).
