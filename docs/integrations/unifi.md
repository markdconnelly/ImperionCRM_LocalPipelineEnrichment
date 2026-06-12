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

## Credential (per customer — company credential)

Key Vault **`conn-company-unifi`** (the Settings company-credential card pattern, like
`conn-company-darkwebid`): a JSON blob `{ "apiKey": "...", "connectionType":
"console"|"cloud", "host": "<console host>" }`, read at task time via the cert SP
(`Get-ImperionKeyVaultSecret`). One client's credential is already provisioned.
**Frontend follow-up:** extending the company-credential provider enum with `unifi`
(analog of migration 0042) goes through the schema-handoff process.

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

**Until the migration lands, the task is DOUBLE-GATED** (credential + table): it logs a
Warn and exits cleanly; the first run after the grants land converges (idempotent,
change-detected upsert).

## Cadence & fields

Daily (`scheduled-tasks/README.md`). Flat columns (everything else lossless in
`raw_payload`): `name` · `model` · `mac` · `ip_address` · `site` (console site name /
cloud host) · `status` · `firmware_version` · `firmware_updatable` (the compliance
signal) · `adopted` · `last_seen`.

## Cmdlets

- `Invoke-ImperionUniFiRequest` — connect: X-API-Key + nextToken/offset paging.
- `Get-ImperionUniFiDevice` — get: `-ConnectionType console` (sites → devices) or
  `cloud` (per-host device groups); flatten to the proposed bronze shape (source `unifi`).
- `Set-ImperionUniFiDeviceToBronze` — post: `Invoke-ImperionBronzePost` adapter,
  `-ColumnSet` projection, change-detected upsert.
- Task: `scheduled-tasks/unifi/devices.task.ps1` (daily, double-gated).

## Assumptions to confirm on first live run

- Endpoint paths + paging property names per connection type.
- Device field names (`macAddress`/`ipAddress`/`state`/`firmwareVersion`/
  `firmwareUpdatable`/`adoptedAt`/`lastSeen`) and the cloud per-host group shape.
- Console TLS: if the console presents a self-signed certificate, trust it on the host
  (cert store) — the shared HTTP core does not skip certificate validation by design;
  file a follow-up if a controller can't be trusted at the OS level.
