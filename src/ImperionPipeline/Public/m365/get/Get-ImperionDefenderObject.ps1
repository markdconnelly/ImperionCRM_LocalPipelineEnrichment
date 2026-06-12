function Get-ImperionDefenderObject {
    <#
    .SYNOPSIS
        Collect Microsoft Defender XDR incidents and alerts and flatten them to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for the Defender XDR security feed (issue #138;
        front-end migration 0076 / ADR-0059). Pages Graph /security/incidents and
        /security/alerts_v2 (app permissions SecurityIncident.Read.All +
        SecurityAlert.Read.All, already admin-consented) and flattens each to the standard
        flat-table envelope, source 'defender', external_id = the Graph id.

        Distinct from Get-ImperionSentinelObject, which covers Azure Sentinel
        rules/watchlists/workbooks via ARM — this is the Defender XDR incident/alert
        stream via Graph. Each row carries an `entity` discriminator
        (incidents / alerts) that Set-ImperionDefenderToBronze routes on (and projects
        away — the bronze tables have no such column). Alerts carry
        incident_external_id (Graph incidentId) — the layering key that groups alerts
        under their incident and pairs the incident with the Autotask ticket worked for
        it (front-end ADR-0059; the link table itself is NOT written here).

        Returns rows; does not write. Requires Initialize-ImperionContext.
    .PARAMETER TenantId
        Tenant to authenticate against; defaults to the partner tenant.
    .OUTPUTS
        Flat bronze rows (source 'defender') ready for Set-ImperionDefenderToBronze.
    .EXAMPLE
        Get-ImperionDefenderObject | Set-ImperionDefenderToBronze
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }

    $token = Get-ImperionGraphToken -TenantId $TenantId
    $rows = [System.Collections.Generic.List[object]]::new()
    $joinPath = { param($obj, $path) (Get-ImperionPropertyPath -InputObject $obj -Path $path) | Join-ImperionValues }

    $incidents = Invoke-ImperionGraphRequest -Uri 'https://graph.microsoft.com/v1.0/security/incidents' -AccessToken $token
    $incidents | ConvertTo-ImperionFlatObject -Source 'defender' -TenantId $TenantId -ExternalIdProperty 'id' -PropertyMap ([ordered]@{
        entity = { 'incidents' }
        display_name = 'displayName'; severity = 'severity'; status = 'status'
        classification = 'classification'; determination = 'determination'
        assigned_to = 'assignedTo'; redirect_incident_id = 'redirectIncidentId'
        incident_web_url = 'incidentWebUrl'
        custom_tags = { param($i) & $joinPath $i 'customTags' }
        system_tags = { param($i) & $joinPath $i 'systemTags' }
        description = 'description'; summary = 'summary'; resolving_comment = 'resolvingComment'
        created_date_time = 'createdDateTime'; last_update_date_time = 'lastUpdateDateTime'
    }) | ForEach-Object { $rows.Add($_) }

    $alerts = Invoke-ImperionGraphRequest -Uri 'https://graph.microsoft.com/v1.0/security/alerts_v2' -AccessToken $token
    $alerts | ConvertTo-ImperionFlatObject -Source 'defender' -TenantId $TenantId -ExternalIdProperty 'id' -PropertyMap ([ordered]@{
        entity = { 'alerts' }
        # Layering key: groups alerts under their defender_incidents row (ADR-0059).
        incident_external_id = 'incidentId'
        provider_alert_id = 'providerAlertId'; title = 'title'; severity = 'severity'
        status = 'status'; classification = 'classification'; determination = 'determination'
        category = 'category'; service_source = 'serviceSource'
        detection_source = 'detectionSource'; detector_id = 'detectorId'
        assigned_to = 'assignedTo'; actor_display_name = 'actorDisplayName'
        threat_display_name = 'threatDisplayName'; threat_family_name = 'threatFamilyName'
        mitre_techniques = { param($a) & $joinPath $a 'mitreTechniques' }
        alert_web_url = 'alertWebUrl'; incident_web_url = 'incidentWebUrl'
        description = 'description'; recommended_actions = 'recommendedActions'
        first_activity_date_time = 'firstActivityDateTime'; last_activity_date_time = 'lastActivityDateTime'
        created_date_time = 'createdDateTime'; last_update_date_time = 'lastUpdateDateTime'
        resolved_date_time = 'resolvedDateTime'
    }) | ForEach-Object { $rows.Add($_) }

    Write-ImperionLog -Source 'defender' -Message 'Defender XDR objects collected.' -Data @{
        incidents = @($incidents).Count; alerts = @($alerts).Count; rows = $rows.Count
    }
    return $rows.ToArray()
}
