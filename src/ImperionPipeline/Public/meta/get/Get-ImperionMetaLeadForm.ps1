function Get-ImperionMetaLeadForm {
    <#
    .SYNOPSIS
        Collect Meta Lead Ad (leadgen) forms under a Page and flatten them to meta_lead_ad_forms bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for the Meta Lead Ads source (LP #362,
        transferred from backend #424). Enumerates the company Page's lead forms via
        /{PageId}/leadgen_forms using the page token (which must carry leads_retrieval),
        and flattens each to the meta_lead_ad_forms column set (front-end migration 0207).
        Form metadata only — NO submitted PII (the questions, not the answers); the form
        ids feed Get-ImperionMetaLead. Target: bronze `meta_lead_ad_forms` → drives the
        lead_hook config in Invoke-ImperionMetaLeadAdsMerge (local merge ownership,
        ADR-0026). Returns rows; does not write. Requires Initialize-ImperionContext.

        ASSUMED-FIELD-NAMES caveat (the Get-ImperionMetaPagePost precedent): the field
        list follows Meta's published leadgen_forms reference, but Meta versions and
        permission tiers prune fields silently — a field the token cannot read comes back
        absent and its flat column lands NULL; nothing is lost (full payload in
        raw_payload). Verify against a live first run before trusting flat columns.
    .PARAMETER PageId
        The Facebook Page id to enumerate lead forms from (stamped onto each row as page_id).
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant (the Page is
        Imperion's own first-party asset, not client data).
    .PARAMETER Token
        Meta page token override. Defaults to the SecretStore resolution
        (Resolve-ImperionMetaToken, ADR-0013).
    .PARAMETER MaxPages
        Paging cap forwarded to the connect layer. Default 100.
    .EXAMPLE
        Get-ImperionMetaLeadForm -PageId '123456789' -Token $pageToken
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string] $PageId,
        [string] $TenantId,
        [string] $Token,
        [int] $MaxPages = 100
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.LocalTenantId }
    $Token = Resolve-ImperionMetaToken -Token $Token

    $fields = 'name,status,locale,questions,context_card,follow_up_action_url,leads_count,created_time'
    $uri = '{0}/leadgen_forms?fields={1}&limit=100' -f [uri]::EscapeDataString($PageId), $fields

    $forms = @(Invoke-ImperionMetaRequest -Token $Token -Uri $uri -MaxPages $MaxPages)
    foreach ($form in $forms) {
        $form | Add-Member -NotePropertyName '_imperionPageId' -NotePropertyValue $PageId -Force
    }

    # questions / context_card are nested arrays/objects — keep them as compact JSON in the
    # flat text column so the form schema survives without exploding into many columns
    # (the lossless object is also in raw_payload).
    $jsonScalar = {
        param($value)
        if ($null -eq $value) { return $null }
        if ($value -is [string]) { return $value }
        $value | ConvertTo-Json -Compress -Depth 20
    }

    $map = [ordered]@{
        page_id              = '_imperionPageId'
        form_name            = 'name'
        status               = 'status'
        locale               = 'locale'
        questions            = { & $jsonScalar (Get-ImperionMember $_ 'questions') }
        context_card         = { & $jsonScalar (Get-ImperionMember $_ 'context_card') }
        follow_up_action_url = 'follow_up_action_url'
        leads_count          = 'leads_count'
        created_time         = 'created_time'
    }

    $forms | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'meta_lead_ad' -TenantId $TenantId -ExternalIdProperty 'id'
}
