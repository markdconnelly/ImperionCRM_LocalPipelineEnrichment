@{
    RootModule        = 'ImperionPipeline.psm1'
    ModuleVersion     = '0.2.0'
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
        # Golden state / drift
        'Set-ImperionPolicyGoldenState',
        'Get-ImperionPolicyDrift',
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
        'Invoke-ImperionITGlueRequest',
        'Set-ImperionITGlueFlexibleAsset',
        # Per-API connect layer (reusable connection / paged-request utilities)
        'Get-ImperionAutotaskZone',
        'Invoke-ImperionAutotaskRequest',
        'Invoke-ImperionTelivyRequest',
        'Invoke-ImperionDarkWebIdRequest',
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
        'Get-ImperionITGlueOrganization',
        'Get-ImperionITGlueContact',
        'Get-ImperionITGlueConfiguration',
        'Get-ImperionTelivyReport',
        'Get-ImperionDarkWebIdCompromise',
        # Per-object post layer (write flattened rows -> bronze; change-detected upsert)
        'Set-ImperionAutotaskContractToBronze',
        'Set-ImperionAutotaskTicketToBronze',
        'Set-ImperionTelivyReportToBronze',
        'Set-ImperionDarkWebIdCompromiseToBronze'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
