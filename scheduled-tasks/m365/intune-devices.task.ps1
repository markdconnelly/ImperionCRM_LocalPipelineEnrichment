# m365/intune-devices - daily Intune managedDevices device-compliance feed -> bronze
# (intune_managed_devices, issue #75 / front-end ADR-0051 decision 6: per device, unreduced;
# the ONLY source of device-level posture indicators - never proxied from tenant level).
# Cadence: Daily (scheduled-tasks/README.md). Composes one get + one post; keep this short
# (CLAUDE.md §1). Single-tenant against the Imperion company tenant by default (Mark's
# 2026-06-11 authorization; GDAP fan-out deferred) - set IMPERION_M365_TENANT_IDS to a
# comma-separated list of customer tenant ids when fan-out resumes (per-tenant isolation:
# each row is stamped with its owning tenant).
#
# GATED: the intune_managed_devices bronze table needs the front-end migration (schema
# handoff, issue #75 comment) - until it lands the post fails loudly; the catch below logs
# a Warn and exits cleanly so the schedule never crashes.
#
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion m365 intune devices' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\m365\intune-devices.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

try {
    $tenantIds = @($env:IMPERION_M365_TENANT_IDS -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($tenantIds.Count -eq 0) {
        Get-ImperionM365Device | Set-ImperionIntuneManagedDeviceToBronze
    }
    else {
        foreach ($tenantId in $tenantIds) {
            Get-ImperionM365Device -TenantId $tenantId | Set-ImperionIntuneManagedDeviceToBronze
        }
    }
}
catch {
    # Schema/permission gate: log loudly and exit; the operator lands the migration /
    # consent and the next run converges (idempotent, change-detected upsert).
    Write-ImperionLog -Level Warn -Source 'm365' -Message "Intune managed-device sync skipped: $($_.Exception.Message)"
}
