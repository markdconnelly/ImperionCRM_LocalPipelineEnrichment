# Azure PostgreSQL firewall / home-IP runbook

The home server connects to Azure Database for PostgreSQL with a **short-lived Entra token**
(ADR-0003) over TLS. Azure must allow the home WAN IP.

## The problem
A **dynamic residential IP** silently breaks unattended runs when it changes — connections
start failing with timeouts/auth errors that look like a credential problem but are a
firewall block.

## Options (pick one, document the choice)
1. **Static IP** from the ISP (cleanest).
2. **VPN / private connectivity** into the Azure VNet (best long-term; removes the public
   firewall rule entirely once a private endpoint exists).
3. **IP-refresh task** — a small scheduled task detects the current WAN IP and updates the
   PostgreSQL firewall rule via ARM (the cert app would need a **scoped write** to that
   firewall rule — an explicit, approved grant beyond read-only; prefer options 1–2).

## Setup checklist
- [ ] Postgres Entra admin configured; `pgaadauth_create_principal` for the SP.
- [ ] DB role GRANTs scoped to the pipeline tables only.
- [ ] Firewall rule for the home WAN IP (or VNet rule).
- [ ] `sslmode=require` enforced.
- [ ] Token resource = `https://ossrdbms-aad.database.windows.net/.default`.

## Symptoms → cause
- `connection timed out` / `no pg_hba.conf entry` → firewall (IP changed or missing rule).
- `password authentication failed` → token expired/wrong resource, or SP role missing.
