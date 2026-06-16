function Invoke-ImperionPurviewComplianceSync {
    <#
    .SYNOPSIS
        Pull Microsoft Purview compliance policies (config + state) into bronze and report drift against golden.
    .DESCRIPTION
        Posture collector (CLAUDE.md §6) for Microsoft Purview compliance configuration (issue #196,
        ADR-0019 §2; front-end migration 0119). Purview enters the security-posture set as POSTURE
        ONLY — configuration + compliance state — exactly mirroring Invoke-ImperionPolicySync and the
        existing Secure Score / Conditional Access / Intune / Defender XDR golden-state/drift engine
        (ADR-0008/0010). It adds NO new drift mechanism: 'purview-compliance' is just another policy
        family in Get-ImperionPolicyCatalog, so Set-ImperionPolicyGoldenState (human-gated) and
        Get-ImperionPolicyDrift work over it unchanged, and it rolls into Invoke-ImperionPostureMerge
        like the others.

        PURVIEW ALERTS ARE EXPLICITLY NOT INGESTED (ADR-0019 §2 — posture only). This cmdlet reads
        only compliance policy config + state.

        Reads observed compliance policies via read-only Graph (the per-client onboarding app,
        CLAUDE.md §3 / pipeline ADR-0018), flattens to purview_compliance_policies with change
        detection, then evaluates drift for the 'purview-compliance' family and logs the summary.
        Promotion of a current policy to the golden baseline (purview_compliance_golden) is the
        human-gated Set-ImperionPolicyGoldenState -PolicyType purview-compliance, as for every golden
        state (ADR-0008). Requires Initialize-ImperionContext.

        CONFIRM BEFORE LIVE USE: the Purview compliance Graph surface + field names below are modeled
        from the documented API but UNVERIFIED against a live consented tenant. Each flat column leads
        with the most likely source name; an unmatched column lands NULL and nothing is lost (full
        payload in raw_payload) — the existing posture-collector precedent. If a Purview pull turns
        out to need a distinct Graph scope, that is a named, human-gated grant addition (CLAUDE.md
        §8), recorded here — never invented silently.
    .PARAMETER TenantId
        Tenant to poll; defaults to the partner tenant.
    .PARAMETER PolicyUri
        Graph endpoint for Purview compliance policies (override for live-shape confirmation).
    .EXAMPLE
        Invoke-ImperionPurviewComplianceSync
    #>
    [CmdletBinding()]
    param(
        [string] $TenantId,
        [string] $PolicyUri = 'https://graph.microsoft.com/beta/security/dataSecurityAndGovernance/compliancePolicies'
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }
    $started = Get-Date
    $graph = Get-ImperionGraphToken -TenantId $TenantId
    $conn = New-ImperionDbConnection

    try {
        $policies = Invoke-ImperionGraphRequest -Uri $PolicyUri -AccessToken $graph

        # Column set of purview_compliance_policies (front-end migration 0119): policy config + state.
        $map = [ordered]@{
            policy_id        = 'id'
            policy_name      = { param($p) $n = Get-ImperionPropertyPath -InputObject $p -Path 'displayName'; if ($n) { $n } else { Get-ImperionPropertyPath -InputObject $p -Path 'name' } }
            policy_type      = { param($p) $t = Get-ImperionPropertyPath -InputObject $p -Path 'policyType'; if ($t) { $t } else { Get-ImperionPropertyPath -InputObject $p -Path '@odata.type' } }
            state            = { param($p) $s = Get-ImperionPropertyPath -InputObject $p -Path 'state'; if ($s) { $s } else { Get-ImperionPropertyPath -InputObject $p -Path 'status' } }
            scope            = 'scope'
            last_modified_at = { param($p) $m = Get-ImperionPropertyPath -InputObject $p -Path 'lastModifiedDateTime'; if ($m) { $m } else { Get-ImperionPropertyPath -InputObject $p -Path 'modifiedDateTime' } }
        }

        if (-not $policies -or @($policies).Count -eq 0) {
            Write-ImperionLog -Source 'm365' -Message 'purview_compliance_policies: 0 items.'
        }
        else {
            $flat = $policies | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'm365' -TenantId $TenantId -ExternalIdProperty 'id'
            $tally = Invoke-ImperionBronzeUpsert -Connection $conn -Table 'purview_compliance_policies' -Rows $flat
            Write-ImperionLog -Level Metric -Source 'm365' -Message 'purview_compliance_policies synced.' -Data @{
                scanned = $tally.scanned; inserted = $tally.inserted; updated = $tally.updated; unchanged = $tally.unchanged
            }
        }

        # Drift against the golden baseline — the existing engine, scoped to the Purview family.
        $drift = Get-ImperionPolicyDrift -Connection $conn -TenantId $TenantId -PolicyType 'purview-compliance'
        $byStatus = $drift | Group-Object status | ForEach-Object { "$($_.Name)=$($_.Count)" }
        Write-ImperionLog -Level Metric -Source 'm365' -Message 'Purview compliance drift evaluated.' -Data @{ summary = ($byStatus -join ' ') }
    }
    finally { $conn.Dispose() }

    Write-ImperionLog -Level Metric -Source 'm365' -Message 'Purview compliance sync complete.' -Data @{
        tenant = $TenantId; seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
    }
}
