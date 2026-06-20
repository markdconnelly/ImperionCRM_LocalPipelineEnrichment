# unifi/devices - daily UniFi device inventory + config-compliance pull -> bronze (unifi_devices).
# Cadence: Daily (scheduled-tasks/README.md). One line: the multi-console sweep (CLAUDE.md §1).
#
# UniFi is now a per-CLIENT, per-CONSOLE credential in the `connection` registry (ADR-0103 /
# backend #229), resolved per row by Invoke-ImperionUniFiDeviceSync (#259) - NOT the old single
# conn-company-unifi JSON blob. The sweep is fail-closed per console and dormant-safe (no active
# rows -> logs and no-ops), so it is safe to schedule before any console is registered.
#
# Still GATED on the front-end migration: the unifi_devices bronze table needs the schema
# handoff (docs/integrations/unifi.md) - each console's upsert fails loudly (and is skipped)
# until it lands. The first run after the table + an active registry row exist converges
# (idempotent, change-detected upsert).
#
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion unifi devices' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\unifi\devices.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

Invoke-ImperionUniFiDeviceSync
