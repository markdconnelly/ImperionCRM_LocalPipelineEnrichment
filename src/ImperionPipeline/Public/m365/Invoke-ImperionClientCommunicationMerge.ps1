function Invoke-ImperionClientCommunicationMerge {
    <#
    .SYNOPSIS
        Merge the home-tenant M365 comms bronze into silver client_communication, filtered to DB clients (LP #395, ADR-0126).
    .DESCRIPTION
        The bronze→silver merge for the unified, client-scoped communications ledger
        (front-end migration 0211, epic markdconnelly/ImperionCRM#1366; ADR-0126), owned by
        this repo on the merge-co-locates-with-ingestion precedent (ADR-0026; the Meta 0075 /
        posture-merge pattern). It projects Imperion's OWN-tenant comms — collected by the
        M365 comms collectors (Invoke-ImperionM365MailSync / ...TeamsChatSync /
        ...TeamsMeetingSync → m365_mail_messages, m365_teams_chats, m365_teams_meetings,
        migration 0065) — into client_communication, retaining ONLY messages that touch a DB
        client and dropping internal / unattributable traffic.

        THE FILTER RULE (the entity's defining contract, front-end migration 0211 +
        docs/database/client-communication-filter.md). For each bronze row the merge gathers
        every participant address (email: from + to + cc; chat: members; meeting: organizer +
        attendees), splits the Imperion side from the non-Imperion side by domain
        (-ImperionDomain, default imperionllc.com), and resolves the client side to a DB
        account by, in precedence order:
          1. exact onboarded-contact email match (contact.email) → stamps account_id + contact_id
             when EXACTLY ONE distinct contact resolves;
          2. else account_domain.domain match → stamps account_id (contact_id NULL) when
             EXACTLY ONE distinct account resolves.
        A row that resolves to no single account is DROPPED (the filter gate) — internal-only
        threads and ambiguous/unknown counterparties never land. The matched account_id (and
        contact_id when a single contact matched) is stamped on the silver row.

        Three idempotent, set-based steps — each INSERT is an upsert on UNIQUE (channel,
        source_system, external_id) with content_hash change detection (the 0211 / ADR-0026
        replace-from-source contract), so a re-run converges and never duplicates (CLAUDE.md §6):

          1. m365_mail_messages   → client_communication (channel email,         source_system m365_email)
          2. m365_teams_chats     → client_communication (channel teams_chat,     source_system m365_teams)
          3. m365_teams_meetings  → client_communication (channel teams_meeting,  source_system m365_teams)

        PII-MINIMAL (ADR-0126 privacy posture): subject/topic only — NO message bodies are
        carried (the M365 comms bronze does not collect bodies; only a short subject/preview).
        snippet stays NULL for the M365 channels. direction is inbound = client→employee,
        outbound = employee→client: derived from the sender (email) / organizer (meeting); a
        Teams chat carries no per-row sender so it lands 'inbound' by convention (a
        client-involved conversation as a single timeline touchpoint). Bronze text timestamps
        are cast with regex guards (the posture-merge pattern) so junk falls back, never throws.

        The social_dm channel (Meta Messenger / IG DMs) is the sibling sink, folded in by
        Invoke-ImperionMetaMerge (LP #383) against contact_social_identity — NOT here.

        GRANTS: migration 0211 grants client_communication SELECT,INSERT,UPDATE to
        `imperion-localpipeline` (the role LP connects as) and `mgid-imperioncrmpipeline`, so
        unlike social_engagement (#357) there is no grant gap. NOT prod-applied until 0211 is
        applied (it is, per the #1366 wave) — the upsert fails loudly and the caller gates it
        until then. Requires Initialize-ImperionContext.
    .PARAMETER Connection
        Optional open Npgsql connection to reuse; otherwise one is opened and disposed.
    .PARAMETER ImperionDomain
        Imperion's own email domain(s) — the "employee side" of the filter. Default
        imperionllc.com. Participants on these domains are never treated as the client side.
    .EXAMPLE
        Invoke-ImperionClientCommunicationMerge
    .EXAMPLE
        Invoke-ImperionClientCommunicationMerge -WhatIf   # show the step plan without touching silver
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        $Connection,
        [string[]] $ImperionDomain = @('imperionllc.com')
    )

    $started = Get-Date
    if (-not $PSCmdlet.ShouldProcess('m365 comms bronze (m365_mail_messages, m365_teams_chats, m365_teams_meetings)', 'merge to client_communication')) { return }

    $ownConnection = -not $Connection
    if ($ownConnection) { $Connection = New-ImperionDbConnection }

    # The Imperion domains as a lower-cased text[] parameter shared by every step's filter.
    $imperionDomains = [string[]]( @($ImperionDomain) | Where-Object { $_ } | ForEach-Object { $_.Trim().ToLowerInvariant() } )

    # The client-resolution tail is identical across channels: from the client-side address
    # array (`client_addrs`), resolve a single account via onboarded contact (preferred,
    # yields contact_id) else account_domain. account_id NULL ⇒ the row is dropped downstream.
    $resolveTail = @"
      CROSS JOIN LATERAL (
        WITH ch AS (
          SELECT DISTINCT c.account_id, c.id AS contact_id
            FROM contact c
           WHERE c.account_id IS NOT NULL AND c.email IS NOT NULL
             AND lower(c.email) = ANY (coalesce(res.client_addrs, '{}'::text[]))
        ),
        dh AS (
          SELECT DISTINCT ad.account_id
            FROM account_domain ad
           WHERE lower(ad.domain) IN (
                   SELECT split_part(p, '@', 2) FROM unnest(coalesce(res.client_addrs, '{}'::text[])) p)
        )
        SELECT
          CASE WHEN (SELECT count(DISTINCT account_id) FROM ch) = 1 THEN (SELECT account_id FROM ch LIMIT 1)
               WHEN (SELECT count(*) FROM dh) = 1               THEN (SELECT account_id FROM dh LIMIT 1)
               ELSE NULL END AS account_id,
          CASE WHEN (SELECT count(*) FROM ch) = 1 THEN (SELECT contact_id FROM ch LIMIT 1)
               ELSE NULL END AS contact_id
      ) acc
"@

    # The ON CONFLICT replace-from-source tail (ADR-0026): refresh only when content_hash moved.
    $onConflictTail = @"
ON CONFLICT (channel, source_system, external_id) DO UPDATE SET
    account_id            = EXCLUDED.account_id,
    contact_id            = EXCLUDED.contact_id,
    direction             = EXCLUDED.direction,
    client_participants   = EXCLUDED.client_participants,
    imperion_participants = EXCLUDED.imperion_participants,
    subject               = EXCLUDED.subject,
    snippet               = EXCLUDED.snippet,
    occurred_at           = EXCLUDED.occurred_at,
    thread_ref            = EXCLUDED.thread_ref,
    content_hash          = EXCLUDED.content_hash
  WHERE client_communication.content_hash IS DISTINCT FROM EXCLUDED.content_hash
"@

    try {
        $tally = [ordered]@{}

        # ── 1. m365_mail_messages → client_communication (channel email) ─────────────
        # Participants = from + to + cc (the collector joins multi-valued cells with '; ').
        # direction by sender domain. occurred_at = received, sent fallback, collected_at last.
        $tally['mail_to_client_communication'] = Invoke-ImperionDbNonQuery -Connection $Connection -Parameters @{ imperionDomains = $imperionDomains } -Sql @"
INSERT INTO client_communication
  (account_id, contact_id, channel, direction, client_participants, imperion_participants,
   subject, snippet, occurred_at, source_system, external_id, thread_ref, content_hash, data_class)
WITH raw AS (
  SELECT b.external_id, b.subject, b.conversation_id, b.content_hash,
         b.received_date_time, b.sent_date_time, b.collected_at,
         lower(trim(b.from_address)) AS from_addr,
         (SELECT array_agg(DISTINCT addr) FROM (
            SELECT lower(trim(x)) AS addr
              FROM unnest(string_to_array(coalesce(b.from_address,''), ';')
                       || string_to_array(coalesce(b.to_addresses,''),  ';')
                       || string_to_array(coalesce(b.cc_addresses,''),  ';')) AS x
             WHERE trim(x) <> '' AND x LIKE '%@%') s) AS participants
    FROM m365_mail_messages b
   WHERE b.source = 'm365_email' AND b.external_id <> ''   -- defense-in-depth vs envelope rows (#133)
),
res AS (
  SELECT r.*,
         (SELECT array_agg(p) FROM unnest(r.participants) p WHERE split_part(p,'@',2) <> ALL (@imperionDomains)) AS client_addrs,
         (SELECT array_agg(p) FROM unnest(r.participants) p WHERE split_part(p,'@',2) =  ANY (@imperionDomains)) AS imperion_addrs
    FROM raw r
)
SELECT acc.account_id, acc.contact_id, 'email'::client_communication_channel,
       CASE WHEN split_part(res.from_addr,'@',2) = ANY (@imperionDomains)
            THEN 'outbound'::client_communication_direction
            ELSE 'inbound'::client_communication_direction END,
       coalesce(res.client_addrs, '{}'::text[]), coalesce(res.imperion_addrs, '{}'::text[]),
       res.subject, NULL,
       CASE WHEN res.received_date_time ~ '^\d{4}-\d{2}-\d{2}' THEN res.received_date_time::timestamptz
            WHEN res.sent_date_time     ~ '^\d{4}-\d{2}-\d{2}' THEN res.sent_date_time::timestamptz
            ELSE res.collected_at::timestamptz END,
       'm365_email', res.external_id, res.conversation_id, res.content_hash, 'client_pii'
  FROM res
$resolveTail
 WHERE acc.account_id IS NOT NULL
$onConflictTail
"@

        # ── 2. m365_teams_chats → client_communication (channel teams_chat) ──────────
        # Chat is conversation-grain (members, topic) with no per-row sender → direction
        # 'inbound' by convention. Participants = member_emails ('; '-joined). thread_ref =
        # the chat id. occurred_at = created, last_updated fallback, collected_at last.
        $tally['teams_chat_to_client_communication'] = Invoke-ImperionDbNonQuery -Connection $Connection -Parameters @{ imperionDomains = $imperionDomains } -Sql @"
INSERT INTO client_communication
  (account_id, contact_id, channel, direction, client_participants, imperion_participants,
   subject, snippet, occurred_at, source_system, external_id, thread_ref, content_hash, data_class)
WITH raw AS (
  SELECT b.external_id, b.topic, b.content_hash,
         b.created_date_time, b.last_updated_date_time, b.collected_at,
         (SELECT array_agg(DISTINCT addr) FROM (
            SELECT lower(trim(x)) AS addr
              FROM unnest(string_to_array(coalesce(b.member_emails,''), ';')) AS x
             WHERE trim(x) <> '' AND x LIKE '%@%') s) AS participants
    FROM m365_teams_chats b
   WHERE b.source = 'm365_teams' AND b.external_id <> ''   -- defense-in-depth vs envelope rows (#133)
),
res AS (
  SELECT r.*,
         (SELECT array_agg(p) FROM unnest(r.participants) p WHERE split_part(p,'@',2) <> ALL (@imperionDomains)) AS client_addrs,
         (SELECT array_agg(p) FROM unnest(r.participants) p WHERE split_part(p,'@',2) =  ANY (@imperionDomains)) AS imperion_addrs
    FROM raw r
)
SELECT acc.account_id, acc.contact_id, 'teams_chat'::client_communication_channel,
       'inbound'::client_communication_direction,
       coalesce(res.client_addrs, '{}'::text[]), coalesce(res.imperion_addrs, '{}'::text[]),
       res.topic, NULL,
       CASE WHEN res.created_date_time      ~ '^\d{4}-\d{2}-\d{2}' THEN res.created_date_time::timestamptz
            WHEN res.last_updated_date_time ~ '^\d{4}-\d{2}-\d{2}' THEN res.last_updated_date_time::timestamptz
            ELSE res.collected_at::timestamptz END,
       'm365_teams', res.external_id, res.external_id, res.content_hash, 'client_pii'
  FROM res
$resolveTail
 WHERE acc.account_id IS NOT NULL
$onConflictTail
"@

        # ── 3. m365_teams_meetings → client_communication (channel teams_meeting) ────
        # Participants = organizer + attendees ('; '-joined). direction by organizer domain.
        # thread_ref = the event id. occurred_at = start, collected_at fallback.
        $tally['teams_meeting_to_client_communication'] = Invoke-ImperionDbNonQuery -Connection $Connection -Parameters @{ imperionDomains = $imperionDomains } -Sql @"
INSERT INTO client_communication
  (account_id, contact_id, channel, direction, client_participants, imperion_participants,
   subject, snippet, occurred_at, source_system, external_id, thread_ref, content_hash, data_class)
WITH raw AS (
  SELECT b.external_id, b.subject, b.content_hash, b.start_date_time, b.collected_at,
         lower(trim(b.organizer_address)) AS organizer_addr,
         (SELECT array_agg(DISTINCT addr) FROM (
            SELECT lower(trim(x)) AS addr
              FROM unnest(string_to_array(coalesce(b.organizer_address,''), ';')
                       || string_to_array(coalesce(b.attendee_addresses,''), ';')) AS x
             WHERE trim(x) <> '' AND x LIKE '%@%') s) AS participants
    FROM m365_teams_meetings b
   WHERE b.source = 'm365_teams' AND b.external_id <> ''   -- defense-in-depth vs envelope rows (#133)
),
res AS (
  SELECT r.*,
         (SELECT array_agg(p) FROM unnest(r.participants) p WHERE split_part(p,'@',2) <> ALL (@imperionDomains)) AS client_addrs,
         (SELECT array_agg(p) FROM unnest(r.participants) p WHERE split_part(p,'@',2) =  ANY (@imperionDomains)) AS imperion_addrs
    FROM raw r
)
SELECT acc.account_id, acc.contact_id, 'teams_meeting'::client_communication_channel,
       CASE WHEN split_part(res.organizer_addr,'@',2) = ANY (@imperionDomains)
            THEN 'outbound'::client_communication_direction
            ELSE 'inbound'::client_communication_direction END,
       coalesce(res.client_addrs, '{}'::text[]), coalesce(res.imperion_addrs, '{}'::text[]),
       res.subject, NULL,
       CASE WHEN res.start_date_time ~ '^\d{4}-\d{2}-\d{2}' THEN res.start_date_time::timestamptz
            ELSE res.collected_at::timestamptz END,
       'm365_teams', res.external_id, res.external_id, res.content_hash, 'client_pii'
  FROM res
$resolveTail
 WHERE acc.account_id IS NOT NULL
$onConflictTail
"@

        $metrics = [ordered]@{ seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 1) }
        foreach ($key in $tally.Keys) { $metrics[$key] = $tally[$key] }
        Write-ImperionLog -Level Metric -Source 'm365' -Message 'Client communication merge complete.' -Data ([hashtable]$metrics)

        return [pscustomobject]$tally
    }
    finally { if ($ownConnection) { $Connection.Dispose() } }
}
