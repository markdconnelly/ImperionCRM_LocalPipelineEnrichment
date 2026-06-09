@{
    # Stable secret NAMES (not values) stored in the SecretStore. Values are added by the
    # bootstrap/operator with Set-Secret; rotated per docs/operations/secret-rotation.md.
    ITGlueReadKey           = 'itglue-read-api-key'
    ITGlueWriteKey          = 'itglue-write-api-key'
    # Autotask: zone is auto-discovered, so no base-uri secret is needed. Field names mirror
    # the live API credential (TrackingIdentifier / Username / Password).
    AutotaskIntegrationCode = 'autotask-integration-code'
    AutotaskUserName        = 'autotask-username'
    AutotaskSecret          = 'autotask-secret'
    KqmApiKey               = 'kqm-api-key'
    KqmBaseUri              = 'kqm-base-uri'
    DocuSignToken           = 'docusign-token'
    ApolloApiKey            = 'apollo-api-key'
    EmbeddingProviderKey    = 'embedding-provider-key'
}
