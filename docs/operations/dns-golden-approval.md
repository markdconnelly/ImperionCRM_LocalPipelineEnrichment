# Runbook — approving a DNS Golden State

**Cmdlet:** `Set-ImperionDnsGoldenState` · **Issue:** local #157 · **Decision:** front-end
ADR-0063, local ADR-0008 (golden/drift) · **Tables:** `dns_golden` (write), `dns_records`
(read) — front-end migration 0080.

## What this is

Approving a **DNS Golden State** freezes a domain's *current* DNS capture as its **approved
baseline**. From then on, the daily silver merge (`Invoke-ImperionDnsMerge`) classifies every
later capture against that baseline as `compliant` / `drift` / `ungoverned` / `missing` and
rolls the result into `dns_domain`. **Until a domain is approved, every record reads
`ungoverned`** — that is correct, not a bug: nothing has been declared "known-good" yet.

This is a **deliberate human gate** (ADR-0063). The pipeline never auto-baselines: approving a
baseline is a posture decision — you are asserting "this is how this domain's DNS *should*
look." Run it only after eyeballing the current capture.

## Preconditions

1. Migrations **0080** (`dns_*`) and **0081** (`account_domain`) applied to prod.
2. The two collectors have run at least once for the domain, so `dns_records` holds a fresh
   capture: `azure/dns-zones` (#155) and `azure/dns-resolve` (#156).
3. Module loaded under the service identity: `Import-Module ImperionPipeline;
   Initialize-ImperionContext`.

## Procedure

1. **Review the current capture first.** Confirm the domain resolves what you expect
   (SPF `-all`, DMARC enforced, the right MX, NS delegating where intended) before freezing it.
   Use the read-only DB or the Security UI — do not approve blind.

2. **Dry-run** (no write):

   ```powershell
   Set-ImperionDnsGoldenState -Domain 'contoso.com' -ApprovedBy 'mark' -WhatIf
   ```

3. **Approve one domain** (default plane = `public`, the ground-truth baseline):

   ```powershell
   Set-ImperionDnsGoldenState -Domain 'contoso.com' -ApprovedBy 'mark'
   ```

   - `-Plane azure` freezes the authoritative Azure-zone config instead of public resolution.
   - `-All` baselines **every** domain in `account_domain` at once — use sparingly and only
     after a fleet-wide review; it is a broad posture assertion.
   - Re-running overwrites the baseline (`ON CONFLICT` — idempotent). Re-approve after an
     intentional DNS change so drift clears.

4. **Confirm.** The next `Invoke-ImperionDnsMerge` (or `azure/dns-merge`, daily) reclassifies:
   the approved records flip from `ungoverned` to `compliant`/`drift`, and `dns_domain.score`
   updates.

## Notes

- **Account scope.** `account_id` is carried onto the golden row from the resolver-stamped
  capture (falling back to `account_domain`), so the per-account read stays isolated.
- **No secrets.** Only domain names + record shapes — no credentials — are read or logged.
- **Audit.** Every approval stamps `golden_approved_by` + `golden_approved_at` and emits a
  Metric log line (`source='dns'`).
