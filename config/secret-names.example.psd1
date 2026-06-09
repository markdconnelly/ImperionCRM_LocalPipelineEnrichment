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

    # Kaseya Quote Manager (KQM) — shape still an assumption; placeholders until provisioned.
    KqmApiKey               = 'kqm-api-key'
    KqmBaseUri              = 'kqm-base-uri'

    # Other CRM/enrichment sources — placeholders until provisioned.
    DocuSignToken           = 'docusign-token'
    ApolloApiKey            = 'apollo-api-key'

    # Voyage AI key for the vectorization stage (ADR-0009; pinned voyage-3-large @ 1024,
    # front-end ADR-0041). Get-ImperionVoyageEmbedding reads this entry.
    EmbeddingProviderKey    = 'embedding-provider-key'

    # NOTE: Dark Web ID has NO local SecretStore secret — in the system it is a COMPANY
    # credential (Key Vault `conn-company-darkwebid`, ADR-0040). Provision a local secret name
    # here only if/when this node polls it directly.
    #
    # NOTE: the Entra app credential is the machine CERTIFICATE (ADR-0002), not a vault secret;
    # the app's ClientId + CertThumbprint live in pipeline.config.psd1. The vault titles
    # `ImperionClientOnboarding-ClientID` / `-Secret` are the client-secret FALLBACK only
    # (cert auth is preferred — see CLAUDE.md §2). Add an entry here if switching to secret auth.
}
