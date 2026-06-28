@{
    # Stable secret NAMES (not values) stored in the SecretStore. Values are added by the
    # bootstrap/operator with Set-Secret; rotated per docs/operations/secret-rotation.md.
    # The values below are the ACTUAL SecretStore secret titles (confirmed with Mark).
    #
    # NOTE (ADR-0029, epic #318): company vendor credentials are moving to DB-authoritative
    # resolution — the `connection` registry row -> keyvault_secret_ref -> Key Vault blob (the
    # same secret the backend/cloud read). As each vendor migrates, its SecretStore mirror title
    # below is NO LONGER consulted; the end-state SecretStore holds ONLY the app credential that
    # mints the Key Vault token. The mirror titles are retained until the per-vendor cleanup PRs
    # land. Already DB-resolved: itglue, televy, quotemanager(kqm), myitprocess, pax8.
    #
    # NOTE (issue #291): IT Glue, KQM (registry provider 'quotemanager') and Telivy now resolve
    # their company API key DIRECTLY from Key Vault under the standardized credential-registry
    # name conn-company-<provider> (the same secret the cloud reads). The SecretStore mirror
    # titles below for those three (ITGlueReadKey, KqmApiKey/KqmApiKeyVaultSecret, TelivyApiKey)
    # are NO LONGER consulted for collection and are retained only pending the cleanup follow-up.
    # The IT Glue *write* path (Set-ImperionITGlueFlexibleAsset, ITGlueWriteKey) is unchanged.

    # IT Glue — one API key in the vault; the export (read) and flexible-asset (write) paths
    # both use it (no separate read/write keys exist).
    ITGlueReadKey           = 'ITGlue-API-Key'
    ITGlueWriteKey          = 'ITGlue-API-Key'

    # Autotask — the three-part API credential. Field meaning -> vault title:
    #   ApiIntegrationCode -> Autotask-API-TrackingIdentifier
    #   UserName           -> Autotask-API-Username
    #   Secret             -> Autotask-API-Password
    # (Zone is auto-discovered by Get-ImperionAutotaskZone, so no base-uri secret is needed.)
    AutotaskIntegrationCode = 'Autotask-API-TrackingIdentifier'
    AutotaskUserName        = 'Autotask-API-Username'
    AutotaskSecret          = 'Autotask-API-Password'

    # Telivy — single API key sent as the x-api-key header (the Postgres source value is 'televy').
    TelivyApiKey            = 'Telivy-API-Key'

    # Kaseya Quote Manager (KQM, issue #98) — read-only REST, key as ?apikey= querystring
    # (URLs are secret-bearing; the retry core redacts them from logs). Resolution order in
    # Resolve-ImperionKqmApiKey:
    #   1. SecretStore title below (when the vault is unlocked this run) — mirror of the KV value
    #   2. Key Vault secret below, read by the cert SP (the ORIGINAL, live in kv-imperioncrm-prd)
    KqmApiKey               = 'kqm-api-key'
    KqmApiKeyVaultSecret    = 'KQM-API-Key'

    # Meta Business Manager (issue #126) — the Business Manager SYSTEM-USER token
    # (non-expiring). Resolution in Resolve-ImperionMetaToken mirrors the KQM pattern:
    # explicit -Token, else the SecretStore mirror below, else the Key Vault original
    # (operator-provisioned, the interim path until #102 bootstraps the SecretStore;
    # ADR-0013). The connect layer sends it as an Authorization: Bearer header
    # (never the querystring) and strips access_token from Meta's paging URLs.
    MetaSystemUserToken     = 'meta-system-user-token'
    MetaTokenVaultSecret    = 'Meta-SystemUser-Token'

    # EasyDMARC (issue #122) — Imperion's 3rd-party DNS/DMARC provider. A COMPANY credential
    # (Imperion's MSP account, not per-client). Read-only REST, key sent as an
    # Authorization: Bearer header (URLs are NOT secret-bearing). Resolution order in
    # Resolve-ImperionEasyDmarcApiKey mirrors KQM/Meta:
    #   1. SecretStore title below (when the vault is unlocked this run) — mirror of the KV value
    #   2. Key Vault secret below, read by the cert SP (the ORIGINAL, kv-imperioncrm-prd)
    # GATED: until provisioned (Mark-gated; plan must include API access), the domains task
    # logs + exits cleanly. See docs/integrations/easydmarc.md.
    EasyDmarcApiKey             = 'easydmarc-api-key'
    EasyDmarcApiKeyVaultSecret  = 'EasyDMARC-API-Key'

    # Other CRM/enrichment sources — placeholders until provisioned.
    # DocuSign (issue #99): the OAuth access token + the eSignature API account id (GUID
    # from the OAuth userinfo endpoint). Tokens EXPIRE — see docs/integrations/docusign.md;
    # the envelopes task logs + exits cleanly until both are provisioned.
    DocuSignToken           = 'docusign-token'
    DocuSignAccountId       = 'docusign-account-id'
    ApolloApiKey            = 'apollo-api-key'

    # Plaud (issue #72): the per-user OAuth token Mark grants once in a browser — raw
    # access token or a JSON blob { access_token, refresh_token, expires_at }. Refresh can
    # break and need a human re-login; the recordings task logs + exits cleanly until then.
    PlaudOAuthToken         = 'plaud-oauth-token'

    # QuickBooks Online (issue #170, time-tracking LP-1 QBO half) — the OAuth2 access token +
    # the realm (company) id. The token EXPIRES (~1h) and the refresh token rotates; the
    # purchases task logs + exits cleanly until both are provisioned (the standing QBO app-
    # registration gate, same blocker as backend #104). Read-only — authoritative payment fact
    # only; the app never pays. See docs/integrations/quickbooks-online.md.
    QboAccessToken          = 'qbo-access-token'
    QboRealmId              = 'qbo-realm-id'

    # MileIQ (issue #167, expense-tracking ADR-0083) - PER-EMPLOYEE read-only OAuth mileage.
    # The BACKEND owns the OAuth handshake and custodies each employee's refresh token in Key
    # Vault (backend MileIQ OAuth issue); this repo only READS the short-lived per-employee
    # ACCESS token. Tokens are keyed by the employee's MileIQ user id, so these are PREFIXES,
    # not single titles: Resolve-ImperionMileIqAccessToken reads `<prefix><mileiqUserId>` from
    # the SecretStore mirror first, else `<vaultPrefix><mileiqUserId>` from Key Vault (the
    # backend-custodied original). A missing secret = that employee is unconnected -> skipped
    # cleanly (dormant-per-employee, fail closed). GATED until the MileIQ External API
    # credentials (markdconnelly/ImperionCRM#495) + backend OAuth custody are live; personal
    # drives never enter, no comp data. See docs/integrations/mileiq.md.
    MileIqTokenPrefix       = 'mileiq-token-'
    MileIqTokenVaultPrefix  = 'MileIQ-Token-'

    # RMM / managed-estate sources (issue #195, ADR-0018) — three MSP-WIDE vendor keys (like
    # Autotask / IT Glue / KQM, NOT per-employee OAuth, NOT per-client onboarding tokens).
    # Resolution mirrors the KQM/EasyDMARC pattern (Resolve-ImperionDattoRmmApiKey /
    # Resolve-ImperionDattoBcdrApiKey / Resolve-ImperionMyItProcessApiKey):
    #   1. SecretStore title below (when the vault is unlocked this run) — mirror of the KV value
    #   2. Key Vault secret below, read by the cert SP (the ORIGINAL, kv-imperioncrm-prd)
    # GATED: until provisioned (Mark-gated), each collector's task logs the gap + exits cleanly.
    # Datto RMM does an API-KEY -> short-lived BEARER exchange (its /auth/oauth/token endpoint),
    # owned by the connect helper; the token is never logged. See docs/integrations/datto-rmm.md,
    # datto-bcdr.md, myitprocess.md.
    DattoRmmApiKey               = 'datto-rmm-api-key'
    DattoRmmApiKeyVaultSecret    = 'Datto-RMM-API-Key'
    DattoBcdrApiKey              = 'datto-bcdr-api-key'
    DattoBcdrApiKeyVaultSecret   = 'Datto-BCDR-API-Key'
    MyItProcessApiKey            = 'myitprocess-api-key'
    MyItProcessApiKeyVaultSecret = 'myITprocess-API-Key'

    # Logistics / procurement sources (issue #198, ADR-0021) — two MSP-WIDE COMPANY credentials
    # (Imperion's own purchasing accounts, NOT per-client). Resolution mirrors the EasyDMARC/Datto
    # pattern (Resolve-ImperionAmazonBusinessToken / Resolve-ImperionCdwApiKey):
    #   1. SecretStore title below (when the vault is unlocked this run) — mirror of the KV value
    #   2. Key Vault secret below, read by the cert SP (the ORIGINAL, kv-imperioncrm-prd)
    # Both sent as an Authorization: Bearer header (URLs are NOT secret-bearing). READ-ONLY — no
    # order is ever placed/modified. GATED: until provisioned (Mark-gated; plan must include API
    # access), each collector's daily task logs the gap + exits cleanly. The front-end bronze
    # migration 0120 (amazon_business_orders / cdw_orders) is already prod-applied; the post writer
    # fails loudly if a table is ever absent. See docs/integrations/logistics-procurement.md.
    AmazonBusinessToken          = 'amazon-business-token'
    AmazonBusinessTokenVaultSecret = 'AmazonBusiness-Token'
    CdwApiKey                    = 'cdw-api-key'
    CdwApiKeyVaultSecret         = 'CDW-API-Key'

    # Pax8 (issue #279, epic #1042) — the MSP's single distributor-account, a COMPANY credential
    # (Imperion's own Pax8 account, NOT per-client). OAuth2 client-credentials: TWO parts — a
    # client id + a client secret — exchanged for a short-lived bearer by Invoke-ImperionPax8Request
    # (the body carries the secret; the retry core redacts it). Resolution in
    # Resolve-ImperionPax8Credential mirrors the Datto/CDW pattern per half:
    #   1. SecretStore title below (when the vault is unlocked this run) — mirror of the KV value
    #   2. Key Vault secret below, read by the cert SP (the ORIGINAL, kv-imperioncrm-prd)
    # GATED: until both are provisioned (Mark-gated), each collector's task logs the gap + exits
    # cleanly. The front-end bronze migration 0161 (pax8_companies/subscriptions/licenses/orders)
    # is authored; the post writer fails loudly if a table is absent. See docs/integrations/pax8-integration.md.
    Pax8ClientId                 = 'pax8-client-id'
    Pax8ClientIdVaultSecret      = 'Pax8-Client-Id'
    Pax8ClientSecret             = 'pax8-client-secret'
    Pax8ClientSecretVaultSecret  = 'Pax8-Client-Secret'

    # Voyage AI key for the vectorization stage (pinned voyage-3-large @ 1024, front-end
    # ADR-0041). Custodied as a PLATFORM-scope AI credential in the `connection` registry
    # (front-end ADR-0129 §8, supersedes ADR-0009's local-secret order; folds #389): the cert
    # SP reads it directly from Key Vault at the canonical name below. The mis-named starter
    # secret (`Voyage-Embedding-API-Key` / SecretStore `embedding-provider-key`) is RETIRED —
    # there is no SecretStore mirror for this key any more.
    EmbeddingProviderKeyVaultSecret = 'conn-platform-voyage'

    # NOTE: Dark Web ID has NO local SecretStore secret — in the system it is a COMPANY
    # credential (Key Vault `conn-company-darkwebid`, ADR-0040). Provision a local secret name
    # here only if/when this node polls it directly.
    #
    # NOTE: the Entra app credential is the machine CERTIFICATE (ADR-0002), not a vault secret;
    # the app's ClientId + CertThumbprint live in pipeline.config.psd1. The vault titles
    # `ImperionClientOnboarding-ClientID` / `-Secret` are the client-secret FALLBACK only
    # (cert auth is preferred — see CLAUDE.md §2). Add an entry here if switching to secret auth.
}
