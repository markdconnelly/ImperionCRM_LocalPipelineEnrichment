function Invoke-ImperionM365DirectoryMerge {
    <#
    .SYNOPSIS
        Fold Entra directory-group membership into the silver contact_enrichment dossier
        (directory_groups fact) — the on-prem twin of the cloud's mergeDirectoryGroups.
    .DESCRIPTION
        The bronze→silver merge for M365 directory groups, owned by THIS repo on the
        merge-co-locates-with-ingestion principle (ADR-0026, generalizing the posture-merge
        precedent ADR-0010): the local pipeline already INGESTS the M365 directory bronze
        (scheduled-tasks/m365/entra-groups + entra-group-members + users → m365_groups /
        m365_group_members / m365_contacts), so it should also MERGE it, rather than the
        cloud Pipeline's 5-min merge-sources timer reaching across for an LP-fed source.
        Ported from ImperionCRM_Pipeline `src/shared/merge-directory.ts` (#93, front-end
        #257 / migration 0079); the cloud copy is ceded once this is live (Pipeline #134).

        What it writes: one `directory_groups` enrichment fact per contact that has ≥1
        Entra group — a JSON array of { id, name } group descriptors — into
        `contact_enrichment`, through the provenance guardrail (CLAUDE.md §5: every field
        carries source + collected_at + lawful_basis or it does not enter the store).
        Lawful basis is `legitimate_interest`: directory-group membership is internal
        operational data about how to work with a person, not public-source enrichment
        (`public_data`) nor a consented field. Enrichment feeds the profile + ledger; it
        NEVER unlocks outbound — the `current_consent` gate still governs contact.

        Join contract (front-end migration 0079, mirrored from merge-directory.ts):
          m365_group_members.member_external_id = m365_contacts.external_ref = the Entra
          user object id; m365_contacts.contact_id is the link to silver `contact`; each
          edge's group resolves to m365_groups by (tenant_id, external_id) for its name.

        Idempotent and set-based — TWO statements, not a per-row loop:
          1. DELETE every prior `m365_directory` fact (so a contact whose membership
             dropped to zero between runs has its stale fact removed).
          2. INSERT one row per contact WITH membership (inner JOIN to m365_group_members),
             so re-running converges and never duplicates. A distinct `m365_directory`
             source label keeps this fact independently convergent — it never clobbers
             another source's contact_enrichment facts.

        The latest member `collected_at` (text in bronze, 0079) is the fact's provenance
        timestamp, regex-guarded before the cast (the posture/meta-merge pattern) so junk
        lands `now()` and never throws. Requires Initialize-ImperionContext.
    .PARAMETER Connection
        Optional open Npgsql connection to reuse; otherwise one is opened and disposed.
    .EXAMPLE
        Invoke-ImperionM365DirectoryMerge
    .EXAMPLE
        Invoke-ImperionM365DirectoryMerge -WhatIf   # show the plan without touching silver
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        $Connection
    )

    $started = Get-Date
    if (-not $PSCmdlet.ShouldProcess('m365 directory bronze (m365_group_members → contact_enrichment)', 'merge to silver')) { return }

    $ownConnection = -not $Connection
    if ($ownConnection) { $Connection = New-ImperionDbConnection }

    try {
        $tally = [ordered]@{}

        # ── 1. Clear this source's prior facts ───────────────────────────────────
        # Replace-from-source idempotency (writeContactEnrichment per-source semantics,
        # done set-based): drop every m365_directory fact, then re-insert the current set.
        # A contact that dropped all its groups loses its stale fact here and is not
        # re-inserted below — exactly the cloud merge's "clear when membership is zero".
        $tally['stale_cleared'] = Invoke-ImperionDbNonQuery -Connection $Connection -Sql @"
DELETE FROM contact_enrichment WHERE source = 'm365_directory'
"@

        # ── 2. Resolve membership → directory_groups fact, one row per contact ────
        # Inner JOIN to m365_group_members: only contacts WITH membership get a fact (the
        # FILTER + HAVING guard the degenerate all-null-group case). value_json is the
        # { id, name } array; value_text is NULL (this is a structured fact). observed_at
        # is the latest edge collected_at, regex-guarded (bronze stores it as text, 0079).
        $tally['contacts_enriched'] = Invoke-ImperionDbNonQuery -Connection $Connection -Sql @"
INSERT INTO contact_enrichment
    (contact_id, attribute_key, value_text, value_json, confidence, source, lawful_basis, observed_at, expires_at)
SELECT c.contact_id,
       'directory_groups',
       NULL,
       jsonb_agg(
           DISTINCT jsonb_build_object(
               'id',   gm.group_external_id,
               'name', coalesce(nullif(g.display_name, ''), gm.group_external_id)
           )
       ) FILTER (WHERE gm.group_external_id IS NOT NULL),
       1,
       'm365_directory',
       'legitimate_interest'::lawful_basis,
       CASE WHEN max(gm.collected_at) ~ '^\d{4}-\d{2}-\d{2}' THEN max(gm.collected_at)::timestamptz
            ELSE now() END,
       NULL
  FROM m365_contacts c
  JOIN m365_group_members gm
        ON gm.member_external_id = c.external_ref
  LEFT JOIN m365_groups g
        ON g.tenant_id   = gm.tenant_id
       AND g.external_id = gm.group_external_id
 WHERE c.contact_id IS NOT NULL
   AND c.external_ref IS NOT NULL
 GROUP BY c.contact_id
HAVING count(gm.group_external_id) FILTER (WHERE gm.group_external_id IS NOT NULL) > 0
"@

        $metrics = [ordered]@{ seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 1) }
        foreach ($key in $tally.Keys) { $metrics[$key] = $tally[$key] }
        Write-ImperionLog -Level Metric -Source 'm365' -Message 'M365 directory merge complete.' -Data ([hashtable]$metrics)

        return [pscustomobject]$tally
    }
    finally { if ($ownConnection) { $Connection.Dispose() } }
}
