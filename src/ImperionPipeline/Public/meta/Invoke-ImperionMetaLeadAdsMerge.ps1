function Invoke-ImperionMetaLeadAdsMerge {
    <#
    .SYNOPSIS
        Merge the Meta Lead Ads bronze into silver: ONE facebook_lead hook + a lead capture per submitted lead.
    .DESCRIPTION
        The bronze→silver merge for the Meta Lead Ads source (LP #362, transferred from
        backend #424), owned by this repo on the merge-co-locates-with-ingestion precedent
        (ADR-0026; grants from front-end migration 0207 + the silver write surface already
        granted by 0075). Ad Lead → capture-inbox lead (front-end ADR-0124 decision 6);
        source = meta_lead_ad. Four idempotent, set-based steps — every INSERT is gated by
        NOT EXISTS, so a re-run converges and never duplicates (CLAUDE.md §6):

          1. Ensure exactly ONE lead_hook (kind facebook_lead, name 'Facebook Lead Ads'),
             config carrying source=meta_lead_ad + the page id. Keyed (kind, name).
          2. For each submitted lead with a resolvable facebook identity not yet known,
             create a minimal contact + facebook contact_social_identity. The identity's
             external_id is the submitter's email when present (the stable cross-form key),
             else 'leadgen:<leadgen_id>' (every lead still resolves to a contact).
          3. ONE lead_capture_event per submitted lead, keyed on
             (hook, payload_bronze->>'leadgen_id') — IDEMPOTENT ON THE META LEADGEN ID
             (the #424 spec). payload_bronze carries source=meta_lead_ad, the leadgen id,
             form/ad/campaign ids, and the field-data answers (PII-adjacent — the row is
             access-controlled; never logged).

        field_data answers are stored as bronze text JSON; the merge reads the convenience
        flat columns (email/full_name/phone_number) the collector already extracted. Bronze
        text timestamps are cast with a regex guard (the posture-merge pattern) so junk
        lands as the collected_at fallback, never throws. INSERT-only — never UPDATE/DELETE
        on silver (the 0075/0207 grant posture). Requires Initialize-ImperionContext.
    .PARAMETER Connection
        Optional open Npgsql connection to reuse; otherwise one is opened and disposed.
    .EXAMPLE
        Invoke-ImperionMetaLeadAdsMerge
    .EXAMPLE
        Invoke-ImperionMetaLeadAdsMerge -WhatIf   # show the step plan without touching silver
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        $Connection
    )

    $started = Get-Date
    if (-not $PSCmdlet.ShouldProcess('meta lead ads bronze (meta_lead_ads)', 'merge to silver')) { return }

    $ownConnection = -not $Connection
    if ($ownConnection) { $Connection = New-ImperionDbConnection }

    try {
        $tally = [ordered]@{}

        # ── 1. Exactly ONE hook row for the Lead Ads inbox, keyed (kind, name). ───────
        # config stamps source=meta_lead_ad (the ADR-0124 #6 distinction lives here +
        # on each capture payload — lead_hook has no source column) and the page id.
        $tally['lead_hook_ensured'] = Invoke-ImperionDbNonQuery -Connection $Connection -Sql @"
INSERT INTO lead_hook (name, kind, config)
SELECT 'Facebook Lead Ads', 'facebook_lead'::lead_hook_kind,
       jsonb_build_object('source', 'meta_lead_ad',
                          'page_id', (SELECT page_id FROM meta_lead_ads
                                       WHERE page_id IS NOT NULL LIMIT 1))
 WHERE NOT EXISTS (SELECT 1 FROM lead_hook
                    WHERE kind = 'facebook_lead' AND name = 'Facebook Lead Ads')
"@

        # ── 2. Minimal contact + facebook identity for submitters not yet known. ─────
        # Identity external_id = the submitter's email when present (stable across forms),
        # else 'leadgen:<id>' so every lead still resolves to a contact. DISTINCT ON the
        # chosen identity key so one contact is minted per distinct submitter, not per lead.
        $tally['contacts_created'] = Invoke-ImperionDbNonQuery -Connection $Connection -Sql @"
WITH submitter AS (
    SELECT DISTINCT ON (identity_key)
           identity_key, full_name, email
      FROM (
        SELECT COALESCE(NULLIF(lower(email), ''), 'leadgen:' || external_id) AS identity_key,
               full_name, email, external_id, created_time
          FROM meta_lead_ads
         WHERE external_id <> ''
      ) s
     ORDER BY identity_key, created_time
), missing AS (
    SELECT s.* FROM submitter s
     WHERE NOT EXISTS (SELECT 1 FROM contact_social_identity csi
                        WHERE csi.platform = 'facebook' AND csi.external_id = s.identity_key)
), new_contact AS (
    INSERT INTO contact (full_name, attribution)
    SELECT COALESCE(NULLIF(m.full_name, ''), NULLIF(m.email, ''), 'Facebook lead ' || m.identity_key),
           jsonb_build_object('source', 'meta_lead_ad', 'facebook_identity_key', m.identity_key)
      FROM missing m
    RETURNING id, attribution->>'facebook_identity_key' AS identity_key
)
INSERT INTO contact_social_identity (contact_id, platform, external_id, raw)
SELECT nc.id, 'facebook', nc.identity_key,
       jsonb_build_object('source', 'meta_lead_ad', 'identity_key', m.identity_key, 'email', m.email)
  FROM new_contact nc
  JOIN missing m ON m.identity_key = nc.identity_key
"@

        # ── 3. ONE lead_capture_event per submitted lead — IDEMPOTENT ON THE LEADGEN ID. ─
        # Keyed on (hook, payload_bronze->>'leadgen_id'); payload carries source=meta_lead_ad,
        # the leadgen id, attribution ids, and the field-data answers. contact_id resolves via
        # the same email-or-leadgen identity key used in step 2.
        $tally['lead_captures_created'] = Invoke-ImperionDbNonQuery -Connection $Connection -Sql @"
WITH lead AS (
    SELECT external_id AS leadgen_id, form_id, page_id, ad_id, ad_name,
           adset_id, campaign_id, campaign_name, platform, is_organic,
           full_name, email, phone_number, field_data, created_time,
           COALESCE(NULLIF(lower(email), ''), 'leadgen:' || external_id) AS identity_key
      FROM meta_lead_ads
     WHERE external_id <> ''
), hook AS (
    SELECT id FROM lead_hook
     WHERE kind = 'facebook_lead' AND name = 'Facebook Lead Ads'
     LIMIT 1
)
INSERT INTO lead_capture_event (hook_id, payload_bronze, contact_id, status, received_at)
SELECT h.id,
       jsonb_build_object(
           'source', 'meta_lead_ad', 'leadgen_id', l.leadgen_id,
           'form_id', l.form_id, 'page_id', l.page_id,
           'ad_id', l.ad_id, 'ad_name', l.ad_name, 'adset_id', l.adset_id,
           'campaign_id', l.campaign_id, 'campaign_name', l.campaign_name,
           'platform', l.platform, 'is_organic', l.is_organic,
           'full_name', l.full_name, 'email', l.email, 'phone_number', l.phone_number,
           'field_data', l.field_data),
       csi.contact_id, 'new',
       CASE WHEN l.created_time ~ '^\d{4}-\d{2}-\d{2}' THEN l.created_time::timestamptz
            ELSE now() END
  FROM lead l
 CROSS JOIN hook h
  LEFT JOIN LATERAL (
        SELECT contact_id FROM contact_social_identity
         WHERE platform = 'facebook' AND external_id = l.identity_key
         LIMIT 1) csi ON true
 WHERE NOT EXISTS (SELECT 1 FROM lead_capture_event e
                    WHERE e.hook_id = h.id
                      AND e.payload_bronze->>'leadgen_id' = l.leadgen_id)
"@

        $metrics = [ordered]@{ seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 1) }
        foreach ($key in $tally.Keys) { $metrics[$key] = $tally[$key] }
        Write-ImperionLog -Level Metric -Source 'meta_lead_ad' -Message 'Meta Lead Ads merge complete.' -Data ([hashtable]$metrics)

        return [pscustomobject]$tally
    }
    finally { if ($ownConnection) { $Connection.Dispose() } }
}
