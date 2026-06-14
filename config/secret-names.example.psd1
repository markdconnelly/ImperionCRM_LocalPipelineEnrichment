@{
    # Stable secret NAMES (not values) stored in the SecretStore. Values are added by the
    # bootstrap/operator with Set-Secret; rotated per docs/operations/secret-rotation.md.
    # The values below are the ACTUAL SecretStore secret titles (confirmed with Mark).

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
    # bill-payments task logs + exits cleanly until both are provisioned (the standing QBO app-
    # registration gate, same blocker as backend #104). Read-only — authoritative payment fact
    # only; the app never pays. See docs/integrations/quickbooks-online.md.
    QboAccessToken          = 'qbo-access-token'
    QboRealmId              = 'qbo-realm-id'

    # Voyage AI key for the vectorization stage (ADR-0009; pinned voyage-3-large @ 1024,
    # front-end ADR-0041). Resolution order in Get-ImperionVoyageEmbedding:
    #   1. SecretStore title below (when the vault is unlocked this run) — mirror of the KV value
    #   2. Key Vault secret below, read by the cert SP (the ORIGINAL; used in -SkipSecretStore mode)
    EmbeddingProviderKey            = 'embedding-provider-key'
    EmbeddingProviderKeyVaultSecret = 'Voyage-Embedding-API-Key'

    # NOTE: Dark Web ID has NO local SecretStore secret — in the system it is a COMPANY
    # credential (Key Vault `conn-company-darkwebid`, ADR-0040). Provision a local secret name
    # here only if/when this node polls it directly.
    #
    # NOTE: the Entra app credential is the machine CERTIFICATE (ADR-0002), not a vault secret;
    # the app's ClientId + CertThumbprint live in pipeline.config.psd1. The vault titles
    # `ImperionClientOnboarding-ClientID` / `-Secret` are the client-secret FALLBACK only
    # (cert auth is preferred — see CLAUDE.md §2). Add an entry here if switching to secret auth.
}
