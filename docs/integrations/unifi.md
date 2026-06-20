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

## SCHEMA GATE — bronze table does not exist yet

`unifi_devices` needs a **front-end migration** (schema is owned there, ADR-0017; this
repo never creates tables). Proposed DDL (standard local-pipeline envelope, migration-0038
style — submit via the schema handoff):

```sql
CREATE TABLE IF NOT EXISTS unifi_devices (
  name text, model text, mac text, ip_address text, site text, status text,
  firmware_version text, firmware_updatable text, adopted text, last_seen text,
  tenant_id text NOT NULL, source text NOT NULL, external_id text NOT NULL,
  collected_at text NOT NULL, raw_payload jsonb NOT NULL, content_hash text NOT NULL,
  PRIMARY KEY (tenant_id, source, external_id)
);
-- + GRANT SELECT, INSERT, UPDATE ON unifi_devices TO "imperion-localpipeline";
```

Also queued behind the handoff (issue #73 acceptance): compliance/policy columns on
silver `device`, the `unifi` source in the device merge, and the Devices-page surfacing —
all front-end/pipeline work.

**Until the migration lands, the sweep is GATED on the table** (and per-console on an active
registry row): each console logs a Warn and is skipped; the first run after the grants land +
a console is registered converges (idempotent, change-detected upsert). The sweep itself is
dormant-safe — no active rows means it logs and no-ops.

## Cadence & fields

Daily (`scheduled-tasks/README.md`). Flat columns (everything else lossless in
`raw_payload`): `name` · `model` · `mac` · `ip_address` · `site` (console site name /
cloud host) · `status` · `firmware_version` · `firmware_updatable` (the compliance
signal) · `adopted` · `last_seen`.

## Cmdlets

- `Invoke-ImperionUniFiRequest` — connect: X-API-Key + nextToken/offset paging.
- `Get-ImperionUniFiDevice` — get: `-ConnectionType console` (sites → devices) or
  `cloud` (per-host device groups); flatten to the proposed bronze shape (source `unifi`).
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
- Task: `scheduled-tasks/unifi/devices.task.ps1` (daily) → `Invoke-ImperionUniFiDeviceSync`.

## Assumptions to confirm on first live run

- Endpoint paths + paging property names per connection type.
- Device field names (`macAddress`/`ipAddress`/`state`/`firmwareVersion`/
  `firmwareUpdatable`/`adoptedAt`/`lastSeen`) and the cloud per-host group shape.
- Console TLS: if the console presents a self-signed certificate, trust it on the host
  (cert store) — the shared HTTP core does not skip certificate validation by design;
  file a follow-up if a controller can't be trusted at the OS level.
