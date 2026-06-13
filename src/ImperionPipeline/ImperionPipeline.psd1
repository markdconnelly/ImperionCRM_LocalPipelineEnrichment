@{
    RootModule        = 'ImperionPipeline.psm1'
    ModuleVersion     = '0.5.0'
    GUID              = 'b1e7c4a2-6d3f-4f1a-9c2e-7a0d5e8f3b21'
    Author            = 'Mark / Imperion'
    CompanyName       = 'Imperion'
    Description       = 'On-prem ingestion, enrichment, and vectorization engine for ImperionCRM (local pipeline plane).'
    PowerShellVersion = '7.2'

    # Pinned dependencies — see docs/deployment. Not auto-installed at import.
    RequiredModules   = @(
        # @{ ModuleName = 'Microsoft.PowerShell.SecretManagement'; ModuleVersion = '1.1.2' }
        # @{ ModuleName = 'Microsoft.PowerShell.SecretStore';      ModuleVersion = '1.0.6' }
        # @{ ModuleName = 'MSAL.PS';                                ModuleVersion = '4.37.0' }
    )

    FunctionsToExport = @(
        # Runtime / setup
        'Initialize-ImperionContext',
        'Initialize-ImperionUnattended',
        'Register-ImperionTask',
        # Sync cmdlets (scheduled-task entry points)
        'Invoke-ImperionServicePrincipalSync',
        'Invoke-ImperionAzureInventorySync',
        'Invoke-ImperionSecureScoreSync',
        'Invoke-ImperionPolicySync',
        'Invoke-ImperionITGlueExport',
        'Invoke-ImperionKaseyaImport',
        'Invoke-ImperionKnowledgeSync',
        # Golden state / drift
        'Set-ImperionPolicyGoldenState',
        'Get-ImperionPolicyDrift',
        'Invoke-ImperionPostureMerge',
        'Invoke-ImperionPostureSnapshot',
        'Get-ImperionSecureScore',
        # Building blocks (reusable helpers)
        'Write-ImperionLog',
        'Get-ImperionContentHash',
        'ConvertTo-ImperionFlatObject',
        'Join-ImperionValues',
        'Connect-ImperionSecretStore',
        'Get-ImperionAccessToken',
        'Open-ImperionDbConnection',
        'Invoke-ImperionDbQuery',
        'Invoke-ImperionDbNonQuery',
        'Invoke-ImperionBronzeUpsert',
        'Invoke-ImperionGraphRequest',
        'Invoke-ImperionArmRequest',
        'Get-ImperionKeyVaultSecret',
        'Invoke-ImperionITGlueRequest',
        'Set-ImperionITGlueFlexibleAsset',
        # Per-API connect layer (reusable connection / paged-request utilities)
        'Get-ImperionAutotaskZone',
        'Invoke-ImperionAutotaskRequest',
        'Invoke-ImperionTelivyRequest',
        'Invoke-ImperionDarkWebIdRequest',
        'Invoke-ImperionDocuSignRequest',
        'Invoke-ImperionUniFiRequest',
        'Invoke-ImperionPlaudRequest',
        'Invoke-ImperionKqmRequest',
        'Invoke-ImperionMetaRequest',
        'Get-ImperionMetaPageToken',
        # Per-object get layer (collect -> flatten to PSObject; no writes)
        'Get-ImperionAutotaskCompany',
        'Get-ImperionAutotaskContact',
        'Get-ImperionAutotaskContract',
        'Get-ImperionAutotaskTicket',
        'Get-ImperionM365User',
        'Get-ImperionM365Device',
        'Get-ImperionM365Mail',
        'Get-ImperionM365TeamsChat',
        'Get-ImperionM365TeamsMeeting',
        'Get-ImperionAzureSubscription',
        'Get-ImperionAzureResourceGroup',
        'Get-ImperionAzureResource',
        'Get-ImperionSentinelObject',
        'Get-ImperionDefenderObject',
        'Get-ImperionEntraAuthMethod',
        'Get-ImperionITGlueOrganization',
        'Get-ImperionITGlueContact',
        'Get-ImperionITGlueConfiguration',
        'Get-ImperionTelivyReport',
        'Get-ImperionDarkWebIdCompromise',
        'Get-ImperionDocuSignEnvelope',
        'Get-ImperionUniFiDevice',
        'Get-ImperionPlaudRecording',
        'Get-ImperionKqmProposal',
        'Get-ImperionKqmFieldName',
        'Get-ImperionMetaPagePost',
        'Get-ImperionMetaPostComment',
        'Get-ImperionMetaConversation',
        'Get-ImperionInstagramMedia',
        'Get-ImperionInstagramComment',
        'Get-ImperionMetaInsight',
        # Per-object post layer (write flattened rows -> bronze; change-detected upsert)
        'Set-ImperionAutotaskContractToBronze',
        'Set-ImperionAutotaskTicketToBronze',
        'Set-ImperionTelivyReportToBronze',
        'Set-ImperionDarkWebIdCompromiseToBronze',
        'Set-ImperionDocuSignContractToBronze',
        'Set-ImperionUniFiDeviceToBronze',
        'Set-ImperionPlaudRecordingToBronze',
        'Set-ImperionKqmProposalToBronze',
        'Set-ImperionM365UserToBronze',
        'Set-ImperionM365DeviceToBronze',
        'Set-ImperionM365MailToBronze',
        'Set-ImperionM365TeamsChatToBronze',
        'Set-ImperionM365TeamsMeetingToBronze',
        'Set-ImperionIntuneManagedDeviceToBronze',
        'Set-ImperionITGlueOrganizationToBronze',
        'Set-ImperionITGlueContactToBronze',
        'Set-ImperionITGlueConfigurationToBronze',
        'Set-ImperionAzureSubscriptionToBronze',
        'Set-ImperionAzureResourceGroupToBronze',
        'Set-ImperionAzureResourceToBronze',
        'Set-ImperionSentinelToBronze',
        'Set-ImperionDefenderToBronze',
        'Set-ImperionEntraAuthMethodToBronze',
        'Set-ImperionMetaPostToBronze',
        'Set-ImperionMetaCommentToBronze',
        'Set-ImperionMetaMessageToBronze',
        'Set-ImperionInstagramMediaToBronze',
        'Set-ImperionInstagramCommentToBronze',
        'Set-ImperionMetaInsightToBronze',
        'Invoke-ImperionMetaMerge',
        'Invoke-ImperionITGlueExportToBronze',
        # Gold knowledge + vectorization (ADR-0009; front-end migration 0045)
        'Get-ImperionKnowledgeAccount',
        'Get-ImperionKnowledgeContact',
        'Get-ImperionKnowledgeContract',
        'Get-ImperionKnowledgeTicket',
        'Get-ImperionKnowledgeDevice',
        'Get-ImperionKnowledgeCredentialExposure',
        'Get-ImperionKnowledgeAssessmentArtifact',
        'Get-ImperionKnowledgeProposal',
        'Get-ImperionKnowledgePosture',
        'Set-ImperionKnowledgeObject',
        'Split-ImperionTextChunk',
        'Get-ImperionVoyageEmbedding',
        'Invoke-ImperionVectorizeKnowledge'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
