function Get-ImperionKnowledgeDevice {
    <#
    .SYNOPSIS
        Compose gold knowledge-object rows for every device in the unified inventory.
    .DESCRIPTION
        Get-layer composer for the gold tier (CLAUDE.md §6/§7, ADR-0009). Mirrors the
        front-end `device_inventory_all` view (migration 0053 / front-end ADR-0047):
        the silver `device` table (migration 0036) is the preferred arm but is empty
        until the per-source device merges land, so the composer also reads the
        not-yet-merged IT Glue configurations (`itglue_export_configurations`,
        migration 0038) — a config that has been merged into silver
        (`itglue_devices.device_id` set) is excluded so devices never double-appear.
        Either arm degrades gracefully to nothing when its tables are empty.

        Thin adapter over the knowledge-composer spine Invoke-ImperionKnowledgeCompose
        (#106): the two-arm union read is a scriptblock -Query; the spine owns the
        scaffold. Output rows are flat PSCustomObjects in the knowledge_object shape
        (entity_type='device', entity_ref = silver device id or IT Glue config id).
        Read-only; pass -Connection to reuse one DB connection across the knowledge sync.
    .PARAMETER Connection
        Optional open Npgsql connection. When omitted, one is opened from config and
        disposed before returning.
    .PARAMETER TenantId
        Owning tenant stamp. Defaults to the partner tenant.
    .OUTPUTS
        Flat knowledge_object rows ready for Set-ImperionKnowledgeObject.
    .EXAMPLE
        Get-ImperionKnowledgeDevice | Set-ImperionKnowledgeObject
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        $Connection,
        [string] $TenantId
    )

    $twoArmDeviceQuery = {
        param($activeConnection)
        # Arm 1 — silver `device` (typed, merge-linked; empty until device merges land).
        $silverDevices = Invoke-ImperionDbQuery -Connection $activeConnection -Sql @'
SELECT d.id::text AS id, d.name, d.device_type, d.manufacturer, d.model, d.serial_number,
       d.os, d.status, d.last_seen_at::text AS last_seen, a.name AS account_name,
       'local-pipeline'::text AS origin
  FROM device d
  LEFT JOIN account a ON a.id = d.account_id
 ORDER BY d.name
'@

        # Arm 2 — not-yet-merged IT Glue configurations (the 450+ real configs), read
        # defensively from BOTH envelope shapes per migration 0053's flagged assumption.
        $itglueConfigurations = Invoke-ImperionDbQuery -Connection $activeConnection -Sql @'
SELECT cfg.external_id AS id, cfg.name,
       COALESCE(cfg.raw_payload->'attributes'->>'configuration-type-name',
                cfg.raw_payload->>'configuration-type-name')   AS device_type,
       COALESCE(cfg.raw_payload->'attributes'->>'manufacturer-name',
                cfg.raw_payload->>'manufacturer-name')          AS manufacturer,
       COALESCE(cfg.raw_payload->'attributes'->>'model-name',
                cfg.raw_payload->>'model-name')                 AS model,
       COALESCE(cfg.raw_payload->'attributes'->>'serial-number',
                cfg.raw_payload->>'serial-number')              AS serial_number,
       COALESCE(cfg.raw_payload->'attributes'->>'operating-system-name',
                cfg.raw_payload->>'operating-system-name')      AS os,
       COALESCE(cfg.raw_payload->'attributes'->>'configuration-status-name',
                cfg.raw_payload->>'configuration-status-name')  AS status,
       cfg.collected_at AS last_seen, a.name AS account_name,
       'itglue'::text AS origin
  FROM itglue_export_configurations cfg
  LEFT JOIN account_bronze_all ab
         ON ab.source = 'itglue' AND ab.external_ref = cfg.organization_id
  LEFT JOIN account a ON a.id = ab.account_id
 WHERE NOT EXISTS (
         SELECT 1 FROM itglue_devices idv
          WHERE idv.external_ref = cfg.external_id AND idv.device_id IS NOT NULL
       )
 ORDER BY cfg.name
'@
        @($silverDevices) + @($itglueConfigurations)
    }

    Invoke-ImperionKnowledgeCompose -EntityType 'device' -Connection $Connection -TenantId $TenantId `
        -EmptyMessage 'knowledge devices: no silver devices or IT Glue configurations found.' `
        -Query $twoArmDeviceQuery `
        -LogData {
        param($deviceRows)
        @{
            silver = @($deviceRows | Where-Object { $_.origin -eq 'local-pipeline' }).Count
            itglue = @($deviceRows | Where-Object { $_.origin -eq 'itglue' }).Count
        }
    } -Compose {
        param($device)
        $title = if ($device.name) { $device.name } else { "Device $($device.id)" }
        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add("Device: $title")
        if ($device.account_name) { $lines.Add("Account: $($device.account_name)") }
        $facts = @(
            if ($device.device_type)   { "type: $($device.device_type)" }
            if ($device.manufacturer)  { "manufacturer: $($device.manufacturer)" }
            if ($device.model)         { "model: $($device.model)" }
            if ($device.serial_number) { "serial: $($device.serial_number)" }
        )
        if ($facts) { $lines.Add(($facts -join ' · ')) }
        $state = @(
            if ($device.os)        { "OS: $($device.os)" }
            if ($device.status)    { "status: $($device.status)" }
            if ($device.last_seen) { "last seen: $($device.last_seen)" }
        )
        if ($state) { $lines.Add(($state -join ' · ')) }
        $lines.Add("Inventory origin: $(if ($device.origin -eq 'itglue') { 'IT Glue configuration (not yet merged to silver)' } else { 'unified silver device record' })")

        [pscustomobject]@{
            entity_ref = [string]$device.id
            title      = $title
            body       = ($lines -join "`n").Trim()
            source     = $device.origin
            metadata   = @{
                account = $device.account_name; device_type = $device.device_type
                status = $device.status; origin = $device.origin
            }
        }
    }
}
