function Get-ImperionSecurityIncident {
    <#
    .SYNOPSIS
        Collect Microsoft security incidents, their alerts, and each alert's evidence → bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for the Microsoft security-incident domain (issue #196,
        ADR-0019). Pages Graph /security/incidents with `$expand=alerts` and flattens the full
        parent→child→grandchild tree to the standard flat-table envelope, source 'm365':

          incident  → m365_incidents   (external_id = the Graph incident id)
          alert     → m365_alerts      (external_id = the Graph alert id;    FK incident_id)
          evidence  → m365_evidence    (external_id = a stable per-evidence id; FK alert_id)

        Each row carries an `entity` discriminator ('incidents' / 'alerts' / 'evidence') that
        Set-ImperionSecurityIncidentToBronze routes on (and projects away — the bronze tables have
        no such column). The full security-fidelity payload (MITRE techniques, detection source,
        entity verdicts, remediation status) is preserved losslessly in raw_payload; the flat
        columns are the queryable subset front-end migration 0119 defines.

        DISTINCT FROM Get-ImperionDefenderObject. That collector lands the Defender XDR feed in the
        OLDER defender_incidents / defender_alerts tables (front-end migration 0076 / ADR-0059) and
        has NO evidence grain and NO autotask_ticket_ref column. THIS collector lands the NEW
        m365_incidents / m365_alerts / m365_evidence set (migration 0119 / ADR-0019) — the
        three-tier security-fidelity payload plus the Microsoft↔Autotask correlation key. The two
        coexist by design (ADR-0019 §1); silver narrows + dedupes downstream.

        AUTOTASK CORRELATION KEY — autotask_ticket_ref (OPEN ITEM, ADR-0019 §1 / Future):
        m365_incidents.autotask_ticket_ref is the Microsoft→Autotask link. Microsoft Graph does NOT
        natively expose an Autotask ticket field; the ref is expected to ride a tag written by the
        MS↔Autotask sync connector (customTags / systemTags) — but its EXACT format is UNCONFIRMED
        (ticket number vs id/GUID vs URL vs connector tag) and so is which tag carries it. Per
        ADR-0019 this collector NEVER invents or silently transforms the value: it captures the raw
        candidate as the API provides it (the first non-empty of the configured tag-candidate paths;
        the full tag set is always in raw_payload) and leaves the format untouched. **This is the
        CONFIRM-BEFORE-LIVE gate** — the candidate path(s) must be verified against real
        m365_incidents rows + the live Autotask ticket shape before the silver stitch is wired. Pass
        -AutotaskRefCandidatePath to point at the confirmed carrier once known.

        AUTH: read-only Graph via the per-client onboarding app (CLAUDE.md §3, pipeline ADR-0018) —
        Get-ImperionGraphToken mints the cert-SP app-only token in the target tenant. Application
        permissions SecurityIncident.Read.All + SecurityAlert.Read.All (read-only; already the
        Defender collector's grant). Per-tenant isolation: every row is stamped with its owning
        tenant; an unconsented tenant is never reached (fail closed).

        Returns rows; does not write. Requires Initialize-ImperionContext.
    .PARAMETER TenantId
        Tenant to authenticate against; defaults to the partner tenant.
    .PARAMETER AutotaskRefCandidatePath
        Ordered candidate property paths on the incident that may carry the Autotask ticket ref;
        first non-empty wins, stored RAW (no transform). Default scans the sync-connector tag
        surfaces ('customTags', 'systemTags') — UNCONFIRMED (ADR-0019 OPEN ITEM). Repoint once the
        real carrier is verified live.
    .OUTPUTS
        Flat bronze rows (source 'm365', entity-discriminated) for Set-ImperionSecurityIncidentToBronze.
    .EXAMPLE
        Get-ImperionSecurityIncident | Set-ImperionSecurityIncidentToBronze
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'AutotaskRefCandidatePath',
        Justification = 'AutotaskRefCandidatePath is consumed inside the $autotaskRef scriptblock closure; the analyzer cannot see the closure-captured read.')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId,
        [string[]] $AutotaskRefCandidatePath = @('customTags', 'systemTags')
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }

    $token = Get-ImperionGraphToken -TenantId $TenantId
    $rows = [System.Collections.Generic.List[object]]::new()
    $joinPath = { param($obj, $path) (Get-ImperionPropertyPath -InputObject $obj -Path $path) | Join-ImperionValues }

    # Raw passthrough of the Autotask ticket ref: first non-empty candidate, value untouched
    # (ADR-0019 OPEN ITEM — never invent or transform; the full tag set survives in raw_payload).
    $autotaskRef = {
        param($incident)
        foreach ($candidate in $AutotaskRefCandidatePath) {
            $value = Get-ImperionPropertyPath -InputObject $incident -Path $candidate
            $flat = $value | Join-ImperionValues
            if ($flat -and "$flat" -ne '') { return $flat }
        }
    }

    # One pull: incidents with their alerts expanded. Evidence rides on each alert (alert.evidence[]).
    $incidents = Invoke-ImperionGraphRequest -AccessToken $token `
        -Uri 'https://graph.microsoft.com/v1.0/security/incidents?$expand=alerts'

    $alertCount = 0
    $evidenceCount = 0
    foreach ($incident in $incidents) {
        $incident | ConvertTo-ImperionFlatObject -Source 'm365' -TenantId $TenantId -ExternalIdProperty 'id' -PropertyMap ([ordered]@{
            entity              = { 'incidents' }
            incident_id         = 'id'
            title               = { param($i) $t = Get-ImperionPropertyPath -InputObject $i -Path 'displayName'; if ($t) { $t } else { Get-ImperionPropertyPath -InputObject $i -Path 'title' } }
            severity            = 'severity'
            status              = 'status'
            classification      = 'classification'
            # Autotask correlation key — RAW passthrough, format UNCONFIRMED (ADR-0019 OPEN ITEM).
            autotask_ticket_ref = { param($i) & $autotaskRef $i }
            assigned_to         = 'assignedTo'
            created_at          = 'createdDateTime'
            last_update_at      = 'lastUpdateDateTime'
        }) | ForEach-Object { $rows.Add($_) }

        $alerts = @(Get-ImperionPropertyPath -InputObject $incident -Path 'alerts')
        foreach ($alert in $alerts) {
            if ($null -eq $alert) { continue }
            $alertCount++
            $alert | ConvertTo-ImperionFlatObject -Source 'm365' -TenantId $TenantId -ExternalIdProperty 'id' -PropertyMap ([ordered]@{
                entity           = { 'alerts' }
                alert_id         = 'id'
                # FK → m365_incidents.incident_id (the layering key).
                incident_id      = { param($a) $iid = Get-ImperionPropertyPath -InputObject $a -Path 'incidentId'; if ($iid) { $iid } else { Get-ImperionPropertyPath -InputObject $incident -Path 'id' } }
                title            = 'title'
                severity         = 'severity'
                category         = 'category'
                mitre_techniques = { param($a) & $joinPath $a 'mitreTechniques' }
                detection_source = 'detectionSource'
                created_at       = 'createdDateTime'
            }) | ForEach-Object { $rows.Add($_) }

            $evidenceItems = @(Get-ImperionPropertyPath -InputObject $alert -Path 'evidence')
            $evidenceIndex = 0
            foreach ($evidence in $evidenceItems) {
                if ($null -eq $evidence) { continue }
                $evidenceCount++
                # Evidence items often lack a stable id; synthesize one (alert id + ordinal) so the
                # upsert key is stable and re-runs converge. The real id (if any) stays in raw_payload.
                $evidenceExternalId = '{0}::{1}' -f (Get-ImperionPropertyPath -InputObject $alert -Path 'id'), $evidenceIndex
                $evidence | Add-Member -NotePropertyName '_imperionEvidenceId' -NotePropertyValue $evidenceExternalId -Force
                $evidence | ConvertTo-ImperionFlatObject -Source 'm365' -TenantId $TenantId -ExternalIdProperty '_imperionEvidenceId' -PropertyMap ([ordered]@{
                    entity             = { 'evidence' }
                    evidence_id        = '_imperionEvidenceId'
                    # FK → m365_alerts.alert_id (captured from the enclosing $alert).
                    alert_id           = { Get-ImperionPropertyPath -InputObject $alert -Path 'id' }
                    # '@odata.type' is a literal key (the dotted-path splitter would mis-read it),
                    # so read it with Get-ImperionMember; fall back to evidenceType.
                    evidence_type      = { param($e) $t = Get-ImperionMember $e '@odata.type'; if ($t) { $t } else { Get-ImperionPropertyPath -InputObject $e -Path 'evidenceType' } }
                    entity_value       = { param($e) $v = Get-ImperionPropertyPath -InputObject $e -Path 'displayName'; if (-not $v) { $v = Get-ImperionPropertyPath -InputObject $e -Path 'entityValue' }; $v }
                    verdict            = 'verdict'
                    remediation_status = 'remediationStatus'
                }) | ForEach-Object { $rows.Add($_) }
                $evidenceIndex++
            }
        }
    }

    Write-ImperionLog -Source 'm365' -Message 'Security incidents collected.' -Data @{
        incidents = @($incidents).Count; alerts = $alertCount; evidence = $evidenceCount; rows = $rows.Count
    }
    return $rows.ToArray()
}
