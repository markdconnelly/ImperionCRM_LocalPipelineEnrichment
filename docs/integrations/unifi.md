# Integration — UniFi device inventory + config compliance → bronze `unifi_devices` (issue #73)

Pulls **UniFi network devices** (switches, APs, gateways) per customer into bronze, with
the **config-compliance signals** the Devices page needs (state, firmware version, an
available-but-unapplied update). Operational/infrastructure data — the flatten→IT Glue→
Postgres path applies (ADR-0006), but the IT Glue flexible-asset half is a **human-gated
follow-up** (new IT Glue write surface, CLAUDE.md §8); this lands the bronze half.

## Two APIs, chosen per site topology (locked design, issue #73 comment 2026-06-10)

| Site topology | API | Base |
| --- | --- | --- |
| HAS a router/gateway (console) | Network Integration API | `https://<console-host>/proxy/network/integration/v1` |
| NO gateway | Site Manager API (cloud) | `https://api.ui.com/v1` |

Both authenticate with an **`X-API-Key`** header. Paging: cloud uses a `nextToken`
cursor; console uses `offset`/`limit` with `totalCount` (both handled by
`Invoke-ImperionUniFiRequest`; property names are assumptions — confirm per controller).

## Credential (per managed client, per console — the credential registry)

UniFi is a **per-client, per-console** credential resolved from the front-end-owned
`connection` registry (ADR-0103 / backend #229), **not** a single company JSON blob. Each
managed-client UniFi console is one `connection` row:

- `scope='client'`, `provider='unifi'`, `status='active'`, linked to the owning customer
  `account` (`account_id`);
- `external_account_id` = the console/site id (the per-console natural key — one account may
  map **many** consoles, many rows);
- `auth_method='api_key'`, `keyvault_secret_ref` = the Key Vault secret NAME holding the API
  key (`conn-client-unifi-<consoleId>`; the value never lands in the DB);
- `provider_config` (jsonb, FE migration 0151 / backend #233) = the **non-secret** console
  config `{ connectionType: 'console'|'cloud', controllerHost? }` (`controllerHost` present
  only for `console`).

The admin registers/rotates a console in the GUI (Settings → Credentials), which POSTs the
backend custody endpoint (`POST /api/connections/client/unifi`); custody writes the key to
Key Vault and the row to the registry. The local sweep then resolves each console's key via
`Resolve-ImperionTenantCredential -Provider unifi` → `@{ ApiKey }` and reads `provider_config`
for the API family + host. **Per-console isolation is absolute** — every bronze row carries
its owning tenant (the account's mapped Microsoft tenant, else the account id), and a console
with no usable credential / consent is skipped, never touched (fail closed, §3/§8).

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
1. **Resolve account.** The bronze envelope `tenant_id` is (per the collector,
   `Resolve-ImperionAccountTenant`) the account's mapped Microsoft tenant when one exists,
   else the account id itself. The merge reverses that in the read: `account_tenant.tenant_id
   = bronze.tenant_id` → `account_id`; else, when the bronze `tenant_id` IS a real
   `account.id`, it is used directly. A row that resolves to **no** account is **skipped**
   (kept in bronze, surfaced as the `unmapped` count) — a network device with no owning
   account is not written.
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

**The sweep self-gates per console on an active registry row:** with no active client UniFi
`connection` rows the sweep logs and no-ops (dormant-safe); a console with no usable
credential is logged + skipped. The first run after a console is registered converges
(idempotent, change-detected upsert).

## Cadence & fields

Daily (`scheduled-tasks/README.md`). Flat columns (everything else lossless in
`raw_payload`): `name` · `model` · `mac` · `ip_address` · `site` (console site name /
cloud host) · `status` · `firmware_version` · `firmware_updatable` (the compliance
signal) · `adopted` · `last_seen`.

## Cmdlets

- `Invoke-ImperionUniFiRequest` — connect: X-API-Key + nextToken/offset paging.
- `Get-ImperionUniFiDevice` — get: `-ConnectionType console` (sites → devices) or
  `cloud` (per-host device groups); flatten to the `unifi_devices` bronze shape (source `unifi`).
  Takes a single explicit `-ApiKey` (the per-console primitive).
- `Set-ImperionUniFiDeviceToBronze` — post: `Invoke-ImperionBronzePost` adapter,
  `-ColumnSet` projection, change-detected upsert.
- **`Invoke-ImperionUniFiDeviceSync`** — the scheduled multi-console fan-out (#259):
  enumerates the active client UniFi `connection` rows, resolves each console's key +
  `provider_config` from the registry, composes `Get-ImperionUniFiDevice` →
  `Set-ImperionUniFiDeviceToBronze` over one shared connection, stamps the owning tenant,
  and is **fail-closed per console** (a bad console is logged + skipped, never blocks the
  rest). Dormant-safe: no active rows → logs and no-ops. Supersedes the single-key shape.
- `Resolve-ImperionAccountTenant` (private) — owning-tenant isolation key for an
  account-scoped source: the account's mapped Microsoft tenant (`account_tenant`), else the
  account id.
- Task: registered scheduled task `Imperion-UniFiDevices` (daily, 02:20; `Register-ImperionTask`,
  ADR-0007 — no loose entry scripts) → `Invoke-ImperionUniFiDeviceSync`.

## Assumptions to confirm on first live run

- Endpoint paths + paging property names per connection type.
- Device field names (`macAddress`/`ipAddress`/`state`/`firmwareVersion`/
  `firmwareUpdatable`/`adoptedAt`/`lastSeen`) and the cloud per-host group shape.
- Console TLS: if the console presents a self-signed certificate, trust it on the host
  (cert store) — the shared HTTP core does not skip certificate validation by design;
  file a follow-up if a controller can't be trusted at the OS level.
