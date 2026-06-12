function Get-ImperionDocuSignEnvelope {
    <#
    .SYNOPSIS
        Collect DocuSign envelopes (signed-contract lifecycle) and flatten them to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6): reads the DocuSign access token + API account id
        from the SecretStore (docusign-token / docusign-account-id) and pages
        /accounts/{accountId}/envelopes (include=recipients) via the connect layer,
        flattening each envelope to the standard flat-table envelope. Target: bronze
        `docusign_contracts` (front-end migration 0038) → silver `contract` via the cloud
        Pipeline's mergeDocusignContractSources (front-end ADR-0044). Returns rows; does
        not write. Requires Initialize-ImperionContext.

        Flat columns mirror the migration-0038 table exactly: subject (emailSubject),
        status, account_ref, sent_at (sentDateTime), completed_at (completedDateTime).
        `account_ref` is the FIRST SIGNER'S EMAIL — the merge accepts an email and matches
        its domain to the silver account (merge-business.ts resolveDocusignAccount), and
        an unmatched ref lands the contract unlinked for a later sweep, never an error.

        CONFIRM BEFORE LIVE USE: base URL pod (na4 default), token freshness (OAuth tokens
        expire — see the connect helper note), and the recipients shape are ASSUMPTIONS
        (ADR-0005 flagged DocuSign "no API access yet"); the bronze table's own columns
        were migrated as assumptions too.
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant.
    .PARAMETER BaseUri
        DocuSign eSignature REST base. Default 'https://na4.docusign.net/restapi/v2.1'
        (placeholder — confirm the account's pod via the OAuth userinfo endpoint).
    .PARAMETER FromDate
        Lower bound for envelope changes (DocuSign requires one). Default '2000-01-01'
        (full backfill); pass a recent date for incremental pulls.
    .EXAMPLE
        Get-ImperionDocuSignEnvelope -FromDate (Get-Date).AddDays(-7).ToString('yyyy-MM-dd')
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId,
        [string] $BaseUri = 'https://na4.docusign.net/restapi/v2.1',
        [string] $FromDate = '2000-01-01'
    )

    $cfg = Get-ImperionConfig
    $names = Get-ImperionSecretNames
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }

    $accessToken = Get-ImperionSecretValue -Name $names.DocuSignToken
    $accountId = Get-ImperionSecretValue -Name $names.DocuSignAccountId

    $uri = '{0}/accounts/{1}/envelopes?from_date={2}&include=recipients&count=100' -f `
        $BaseUri.TrimEnd('/'), [uri]::EscapeDataString($accountId), [uri]::EscapeDataString($FromDate)
    $envelopes = Invoke-ImperionDocuSignRequest -AccessToken $accessToken -Uri $uri -ResolveBaseUri $BaseUri

    $firstSignerEmail = {
        param($envelope)
        $signers = Get-ImperionPropertyPath -InputObject $envelope -Path 'recipients.signers'
        if ($signers) { Get-ImperionMember (@($signers)[0]) 'email' }
    }

    $map = [ordered]@{
        subject      = 'emailSubject'
        status       = 'status'
        account_ref  = { param($envelope) & $firstSignerEmail $envelope }
        sent_at      = 'sentDateTime'
        completed_at = 'completedDateTime'
    }

    $envelopes | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'docusign' -TenantId $TenantId -ExternalIdProperty 'envelopeId'
}
