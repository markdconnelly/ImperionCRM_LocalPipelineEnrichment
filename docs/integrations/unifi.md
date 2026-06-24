# Integration — UniFi device inventory + config compliance → bronze `unifi_devices` (#73; company-scope remodel #321)

Pulls **UniFi network devices** (switches, APs, gateways) per customer into bronze, with
the **config-compliance signals** the Devices page needs (state, firmware version, an
available-but-unapplied update). Operational/infrastructure data — the flatten→IT Glue→
Postgres path applies (ADR-0006), but the IT Glue flexible-asset half is a **human-gated
follow-up** (new IT Glue write surface, CLAUDE.md §8); this lands the bronze half.

## ONE company key, the cloud Site Manager API (company-scope remodel, #321)

UniFi is a **company-scope cloud connector** (FE #1278 / backend #386, ADR-0122). The cloud
**Site Manager API** key (`https://api.ui.com/v1`, `X-API-Key` header) is **MSP-wide**: one
key enumerates **every** client's sites and devices. So the collector resolves the **single**
company key and sweeps the whole estate — it does **not** resolve a per-client/per-console key
(the per-console fan-out #259 is **retired**: UniFi is no longer registered per client, which
is why the old sweep logged "No active client UniFi consoles registered").

Endpoints (paging via `nextToken` cursor, handled by `Invoke-ImperionUniFiRequest`):

| Endpoint | Returns |
| --- | --- |
| `GET /v1/sites` | sites: `siteId`, `hostId`, `meta.name`, `statistics.counts.*` |
| `GET /v1/devices` | per-host groups `{ hostId, hostName, devices[] }` |

## Credential (one company key — the credential registry)

UniFi is one **company-scope** `connection` row: `scope='company'`, `provider='unifi'`,
`status='active'`, `keyvault_secret_ref='conn-company-unifi'` (a JSON blob `{ apiKey }`; the
value never lands in the DB). The admin enters it once on the Connections card; the local
collector resolves it via `Resolve-ImperionCompanyCredential -Provider unifi -Field apiKey`
(ADR-0103 / #319). Dormant-safe: with no active company `unifi` row the sweep logs and
no-ops, never touched (fail closed, §8).

### Site → account mapping (the per-client attribution)

Because one key sees every client, each **device is attributed to its account in the GUI**,
Autotask-pattern: the FE client-mapping unit list keys UniFi on the **`site`** column
(`listClientMappingUnits`), so an admin maps each discovered site → account, written to
`entity_xref(entity_type='account', source_system='unifi', source_key=<site>,
internal_entity_id=<account_id>, match_method='manual')`. The collector reads those mappings
and stamps each device's bronze `tenant_id` with its owning **account id** (so the co-located
merge resolves it directly). A device on a not-yet-mapped site is stamped the **all-zero
sentinel uuid** — a valid uuid that resolves to no account (the merge counts it unmapped) —
but still lands in bronze so the GUI surfaces the site for mapping; the next run re-stamps it
with the real account once mapped.

## Bronze table — landed (front-end migration 0162)

`unifi_devices` is the front-end-owned bronze table (schema is owned there, ADR-0017; this
repo never creates tables). It landed in **front-end migration `0162`** (#1053/#73) and is
**prod-applied** — the table exists with the local-pipeline write grant, but is **EMPTY**
until a console is registered. Shape (standard local-pipeline envelope, all-text bronze;
true types + lossless payload in `raw_payload`):

```sql
CREATE TABLE IF NOT EXISTS unifi_devices (
  name text, model text, mac text, ip_address text, site text, status text,
  firmware_version text, firmware_updatable text, adopted text, last_seen text,
  tenant_id text NOT NULL, source text NOT NULL, external_id text NOT NULL,
  collected_at text NOT NULL, raw_payload jsonb NOT NULL, content_hash text NOT NULL,
  PRIMARY KEY (tenant_id, source, external_id)
);
-- + GRANT SELECT, INSERT, UPDATE ON unifi_devices TO "imperion-localpipeline";
-- + CREATE INDEX ix_unifi_devices_mac ON unifi_devices (mac);  -- merge natural key
```

Merge target is silver `device` (network-infrastructure class, NOT `cloud_asset`); the
`device` OKF concept already names `unifi` as a contributing source (0162). The on-prem
bronze→silver `Invoke-ImperionUniFiMerge` (merge co-locates with ingestion, ADR-0026) is
**BUILT** (issue #284) — see the Merge section below; the Devices-page firmware-compliance
surfacing remains a tracked follow-up (issue #73 acceptance / ImperionCRM #1241).

## Merge — `unifi_devices` bronze → silver `device` (BUILT, issue #284)

`Invoke-ImperionUniFiMerge` runs **after** the UniFi collector (`Imperion-UniFiMerge` @
02:22; merge co-locates with ingestion, ADR-0026) and folds `unifi_devices` bronze into
silver `device` as the **network-infrastructure** class. UniFi gear is physical on-prem
hardware → it feeds `device`, **never `cloud_asset`** (#1053).

### How it works
1. **Resolve account.** The collector stamps the bronze envelope `tenant_id` with the
   device's owning **account id** (from the GUI `entity_xref('account','unifi',site)`
   mapping), or the all-zero sentinel when its site is unmapped. The merge resolves it in
   the read: when `bronze.tenant_id` IS a real `account.id` it is used directly (the
   company-scope path); it also still maps `account_tenant.tenant_id = bronze.tenant_id`
   for any legacy MS-tenant-stamped rows. A row that resolves to **no** account (the
   sentinel, or any unmapped value) is **skipped** (kept in bronze, surfaced as the
   `unmapped` count) — a network device with no owning account is not written.
2. **Match** on `(account_id, lower(btrim(name)))` — the cloud `device-matcher` name tier,
   the only stable natural key available without a `mac` column. UniFi gear has no serial,
   so the serial tier does not apply.
3. **Create** when unmatched: a new `device` with `device_type='network'`,
   `manufacturer='Ubiquiti'`, plus `name`/`model`/`status`/`last_seen_at`.
4. **COALESCE-fill** on a match: fills ONLY currently-NULL identity fields
   (`device_type`/`manufacturer`/`model`/`status`) and advances `last_seen_at` to the
   greater of the two. It **never overwrites** a non-null value — the precedence-safety
   guarantee while `device` has no `source` column: UniFi can enrich a sparse row but
   never demote a higher-authority source's field (`website` > `datto_rmm` > `unifi` …).

Idempotent + resumable: a re-run re-matches the same name within the same account and
re-fills the same nulls (converges, never duplicates). Each bronze row is processed in its
own try/catch so one bad row never blocks the rest (the cloud_asset/posture/Pax8 precedent).

### Schema gaps (ImperionCRM #1241 — Mark-gated)

The `device` OKF concept names `mac` as the UniFi lateral key, `device_type='network'`, and
firmware signals as silver columns. The current silver `device` table has **none** of:
a `mac` column / `(account_id, mac)` unique index; a `source`/precedence column (so a true
replace-from-source scoped to the `unifi` label is impossible); firmware columns; and the
local-pipeline role holds only `SELECT` on `device` (no `INSERT`/`UPDATE`). This repo never
owns schema (CLAUDE.md §5/§6), so until **ImperionCRM #1241** lands the merge is the
**conservative/additive** shape above and runs on **0 rows** (no write grant + empty
bronze). The proper `mac`-keyed precedence merge + firmware-signal surfacing follow once
#1241's schema lands.

**The sweep self-gates on the company key:** with no active company `unifi` `connection`
row the sweep logs and no-ops (dormant-safe). The first run after the company key is entered
converges (idempotent, change-detected upsert).

## Cadence & fields

Daily (`scheduled-tasks/README.md`). Flat columns (everything else lossless in
`raw_payload`): `name` · `model` · `mac` · `ip_address` · `site` (console site name /
cloud host) · `status` · `firmware_version` · `firmware_updatable` (the compliance
signal) · `adopted` · `last_seen`.

## Cmdlets

- `Invoke-ImperionUniFiRequest` — connect: X-API-Key + nextToken paging.
- `Get-ImperionUniFiDevice` — get: takes the one company `-ApiKey` + a `-SiteAccountMap`
  (site → account id); pulls `/v1/sites` (hostId → site name) then `/v1/devices` (per-host
  groups), flattens each device to the `unifi_devices` bronze shape (source `unifi`),
  stamping the owning account id as `tenant_id` (sentinel when unmapped).
- `Set-ImperionUniFiDeviceToBronze` — post: `Invoke-ImperionBronzePost` adapter,
  `-ColumnSet` projection, change-detected upsert.
- **`Invoke-ImperionUniFiDeviceSync`** — the scheduled company-scope sweep (#321): resolves
  the ONE company key (`Resolve-ImperionCompanyCredential -Provider unifi -Field apiKey`),
  reads the `entity_xref` site → account mappings, composes `Get-ImperionUniFiDevice` →
  `Set-ImperionUniFiDeviceToBronze` over one shared connection. Dormant-safe: no company key
  → logs and no-ops. Supersedes the per-console fan-out (#259).
- `Resolve-ImperionCompanyCredential` (private) — reads the company `conn-company-unifi`
  blob's `apiKey` field via the credential registry (ADR-0103 / #319).
- Task: registered scheduled task `Imperion-UniFiDevices` (daily, 02:20; `Register-ImperionTask`,
  ADR-0007 — no loose entry scripts) → `Invoke-ImperionUniFiDeviceSync`.

## API shape — confirmed (secret-safe probe, 2026-06-24)

The `api.ui.com/v1` envelope is `{ data, httpStatusCode, traceId }`. The collector field map
uses the **confirmed live device shape** (no longer the earlier doc-guesses):
`mac` · `ip` · `status` · `version` · `firmwareStatus` · `adoptionTime` (the prior
`macAddress`/`ipAddress`/`state`/`firmwareVersion`/`firmwareUpdatable`/`adoptedAt` were
wrong). The Site Manager device has **no** last-seen field today, so `last_seen` is null
(preserved in `raw_payload`). Still open: paging beyond the first page (cursor confirmed,
multi-page volume not yet observed) and the `/v1/hosts` console-hardware enrichment (raw
payload retains everything for a future pass).
