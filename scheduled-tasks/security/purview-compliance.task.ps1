# security/purview-compliance - daily Microsoft Purview compliance posture pull -> bronze
# (purview_compliance_policies + drift vs purview_compliance_golden, issue #196 /
# front-end migration 0119 + ADR-0019 §2). Cadence: Daily (scheduled-tasks/README.md) -
# compliance config is slow-changing; the change-detected upsert keeps re-runs cheap.
#
# POSTURE ONLY - config + compliance state, NO Purview alerts (ADR-0019 §2). Joins the existing
# golden-state/drift engine unchanged (Get-ImperionPolicyCatalog / Get-ImperionPolicyDrift /
# Set-ImperionPolicyGoldenState -PolicyType purview-compliance, the latter human-gated).
#
# AUTH: read-only Graph via the per-client onboarding app (CLAUDE.md §3, pipeline ADR-0018).
# CONFIRM BEFORE LIVE USE: the Purview compliance Graph surface + field names are modeled from the
# documented API but UNVERIFIED against a live consented tenant; an unmatched flat column lands NULL
# (full payload in raw_payload). If a distinct Graph scope is needed it is a named, human-gated grant
# addition (CLAUDE.md §8). See docs/integrations/purview-compliance.md.
#
# GATED: front-end migration 0119 (purview_compliance_*) is SHIPPED + prod-applied. Remaining gate is
# onboarding-app consent; until then the upsert fails loudly and the catch logs a Warn + exits clean.
#
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion-Purview-Compliance' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\security\purview-compliance.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

try {
    $tenantIds = @($env:IMPERION_M365_TENANT_IDS -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($tenantIds.Count -eq 0) {
        Invoke-ImperionPurviewComplianceSync
    }
    else {
        foreach ($tenantId in $tenantIds) {
            Invoke-ImperionPurviewComplianceSync -TenantId $tenantId
        }
    }
}
catch {
    Write-ImperionLog -Level Warn -Source 'm365' -Message "Purview compliance sync skipped: $($_.Exception.Message)"
}
