function Get-ImperionSemanticCatalog {
    <#
    .SYNOPSIS
        The shared map of silver-tier entities -> live DB relation -> OKF concept file in the
        front-end semantic-layer bundle.
    .DESCRIPTION
        One source of truth used by Get-ImperionSemanticDrift and Invoke-ImperionSemanticDriftSync
        so they always agree on which live silver relation backs which OKF concept file. The bundle
        is owned by markdconnelly/ImperionCRM at docs/database/semantic-layer/tables/<Concept>.md
        (CLAUDE.md section 11 / ADR-0086) — this repo only PROPOSES updates, it never forks the files.

        Relation is the live silver view/table introspected from information_schema (column NAMES
        only — never row data, never PII). Concept is the bundle file basename (no extension).

        This list mirrors the authored subset in the bundle index.md. As the bundle expands
        (front-end #536) new rows are added here so the drift agent covers them too.
    #>
    @(
        [pscustomobject]@{ Concept = 'account';                    Relation = 'account' }
        [pscustomobject]@{ Concept = 'contact';                    Relation = 'contact' }
        [pscustomobject]@{ Concept = 'device';                     Relation = 'device' }
        [pscustomobject]@{ Concept = 'opportunity';                Relation = 'opportunity' }
        [pscustomobject]@{ Concept = 'credential_exposure';        Relation = 'credential_exposure' }
        [pscustomobject]@{ Concept = 'proposal';                   Relation = 'proposal' }
        [pscustomobject]@{ Concept = 'assessment';                 Relation = 'assessment' }
        [pscustomobject]@{ Concept = 'project';                    Relation = 'project' }
        [pscustomobject]@{ Concept = 'task';                       Relation = 'task' }
        [pscustomobject]@{ Concept = 'delivery_template';          Relation = 'delivery_template' }
        [pscustomobject]@{ Concept = 'discovery_call';             Relation = 'discovery_call' }
        [pscustomobject]@{ Concept = 'strategic_business_review';  Relation = 'strategic_business_review' }
        [pscustomobject]@{ Concept = 'ticket';                     Relation = 'ticket' }
        [pscustomobject]@{ Concept = 'interaction';                Relation = 'interaction' }
        [pscustomobject]@{ Concept = 'campaign';                   Relation = 'campaign' }
        [pscustomobject]@{ Concept = 'workflow';                   Relation = 'workflow' }
        [pscustomobject]@{ Concept = 'timesheet';                  Relation = 'timesheet' }
        [pscustomobject]@{ Concept = 'expense_report';             Relation = 'expense_report' }
        [pscustomobject]@{ Concept = 'time_record';                Relation = 'time_record' }
        [pscustomobject]@{ Concept = 'expense_item';               Relation = 'expense_item' }
        [pscustomobject]@{ Concept = 'consent_event';              Relation = 'consent_event' }
        [pscustomobject]@{ Concept = 'posture_snapshot';           Relation = 'posture_snapshot' }
        [pscustomobject]@{ Concept = 'tenant_posture';             Relation = 'tenant_posture' }
        [pscustomobject]@{ Concept = 'dns_domain';                 Relation = 'dns_domain' }
        [pscustomobject]@{ Concept = 'knowledge_object';           Relation = 'knowledge_object' }
        [pscustomobject]@{ Concept = 'app_user';                   Relation = 'app_user' }
        [pscustomobject]@{ Concept = 'connection';                 Relation = 'connection' }
    )
}
