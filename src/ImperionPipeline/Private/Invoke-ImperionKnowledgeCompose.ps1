function Invoke-ImperionKnowledgeCompose {
    <#
    .SYNOPSIS
        The shared knowledge-composer spine: query, relate, compose, hash, log.
    .DESCRIPTION
        Module-internal engine behind every Get-ImperionKnowledge* gold composer
        (CLAUDE.md §6/§7, ADR-0009, issue #106). Owns the scaffold the nine composers
        used to repeat per copy: the partner-tenant default, the own-vs-reuse connection
        lifecycle (ADR-0003 short-lived-token connection), the primary entity query, the
        empty-set short-circuit log, the related-row hashtable grouping caches, the
        knowledge_object row emit (tenant_id / entity_type / entity_ref / title / body /
        summary / source / metadata-json / content_hash over title+body — the idempotency
        key Set-ImperionKnowledgeObject and the vectorizer both honour), and the final
        metric log line. The public composers stay thin adapters that declare SQL plus a
        -Compose scriptblock; behavior is identical to the pre-refactor copies (same row
        shape, same log messages and count keys, same empty-set messages).

        Named Invoke- rather than the issue's New- sketch: the spine is read-only, and a
        New-* verb without SupportsShouldProcess trips
        PSUseShouldProcessForStateChangingFunctions — ShouldProcess would gate a pure read.
    .PARAMETER EntityType
        The knowledge_object entity_type stamped on every emitted row
        ('account', 'contact', 'ticket', …).
    .PARAMETER Query
        The primary entity query. Either a SQL string (run through
        Invoke-ImperionDbQuery) or a scriptblock receiving the open connection and
        returning the entity rows (for composers whose primary read is not one statement,
        e.g. the device two-arm union).
    .PARAMETER RelatedQueries
        Optional hashtable of named side queries grouped into per-key lookup caches:
        name -> @{ Sql = '<select>'; KeyColumn = '<column>' }. Each runs once; its rows
        are grouped into a hashtable of List[object] keyed by the (stringified)
        KeyColumn value. The -Compose block receives the whole set as its second
        argument: $related['<name>']['<key>'].
    .PARAMETER Compose
        Scriptblock invoked once per entity row:
        ($entityRow, $relatedLookups, $context) where $context exposes .Connection and
        .TenantId. Returns the composed fragment as a pscustomobject with entity_ref,
        title, body, source, metadata (hashtable — JSON-serialized here; a
        pre-serialized string passes through), and optionally tenant_id (required under
        -PerRowTenant). Return $null/nothing to skip the row.
    .PARAMETER Connection
        Optional open Npgsql connection to reuse (caller disposes). When omitted, one is
        opened from config and disposed before returning.
    .PARAMETER TenantId
        Owning tenant stamp. Defaults to the partner tenant unless -PerRowTenant.
    .PARAMETER PerRowTenant
        The tenant axis is the data itself (posture): no partner-tenant default is
        applied and every composed fragment must carry its own tenant_id
        (per-tenant isolation, CLAUDE.md §3).
    .PARAMETER LogLabel
        Human label in the log lines ("knowledge <label> composed.",
        default empty message). Defaults to "<EntityType>s".
    .PARAMETER CountName
        Key name for the row count in the final metric log's Data. Defaults to LogLabel
        (the assessment composer logs label 'assessment artifacts' but counts
        'artifacts'; posture counts 'tenants').
    .PARAMETER EmptyMessage
        Log message when the primary query returns nothing. Defaults to
        "knowledge <LogLabel>: nothing to compose.".
    .PARAMETER LogData
        Optional scriptblock receiving the entity rows and returning a hashtable of
        extra fields merged into the final metric log's Data (e.g. the device
        silver/itglue split).
    .OUTPUTS
        Flat knowledge_object rows ready for Set-ImperionKnowledgeObject.
    .EXAMPLE
        # Inside a public composer:
        Invoke-ImperionKnowledgeCompose -EntityType 'contact' -Connection $Connection `
            -TenantId $TenantId -Query $contactSql -EmptyMessage 'knowledge contacts: no silver contacts found.' `
            -Compose { param($contact) ... }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string] $EntityType,
        [Parameter(Mandatory)][object] $Query,
        [hashtable] $RelatedQueries,
        [Parameter(Mandatory)][scriptblock] $Compose,
        $Connection,
        [string] $TenantId,
        [switch] $PerRowTenant,
        [string] $LogLabel,
        [string] $CountName,
        [string] $EmptyMessage,
        [scriptblock] $LogData
    )

    if (-not $LogLabel) { $LogLabel = "${EntityType}s" }
    if (-not $CountName) { $CountName = $LogLabel }
    if (-not $PerRowTenant -and -not $TenantId) { $TenantId = (Get-ImperionConfig).LocalTenantId }

    $ownsConnection = $false
    $activeConnection = $Connection
    if (-not $activeConnection) { $activeConnection = New-ImperionDbConnection; $ownsConnection = $true }
    try {
        $entityRows = if ($Query -is [scriptblock]) { @(& $Query $activeConnection) }
        else { @(Invoke-ImperionDbQuery -Connection $activeConnection -Sql ([string]$Query)) }
        $entityRows = @($entityRows | Where-Object { $null -ne $_ })
        if ($entityRows.Count -eq 0) {
            if (-not $EmptyMessage) { $EmptyMessage = "knowledge ${LogLabel}: nothing to compose." }
            Write-ImperionLog -Source 'knowledge' -Message $EmptyMessage
            return @()
        }

        # Run each related query once and group its rows into a per-key lookup cache.
        $relatedLookups = @{}
        if ($RelatedQueries) {
            foreach ($relatedName in @($RelatedQueries.Keys)) {
                $relatedSpec = $RelatedQueries[$relatedName]
                $lookup = @{}
                Invoke-ImperionDbQuery -Connection $activeConnection -Sql $relatedSpec.Sql | ForEach-Object {
                    $lookupKey = [string](Get-ImperionMember $_ $relatedSpec.KeyColumn)
                    if (-not $lookup.ContainsKey($lookupKey)) {
                        $lookup[$lookupKey] = [System.Collections.Generic.List[object]]::new()
                    }
                    $lookup[$lookupKey].Add($_)
                }
                $relatedLookups[$relatedName] = $lookup
            }
        }

        $composeContext = [pscustomobject]@{ Connection = $activeConnection; TenantId = $TenantId }

        $rows = foreach ($entityRow in $entityRows) {
            $fragment = & $Compose $entityRow $relatedLookups $composeContext
            if ($null -eq $fragment) { continue }

            $fragmentTenant = Get-ImperionMember $fragment 'tenant_id'
            if (-not $fragmentTenant) {
                if ($PerRowTenant) {
                    throw "Invoke-ImperionKnowledgeCompose ($EntityType): -PerRowTenant requires every composed fragment to carry tenant_id."
                }
                $fragmentTenant = $TenantId
            }

            $metadata = Get-ImperionMember $fragment 'metadata'
            $metadataJson = if ($null -eq $metadata) { $null }
            elseif ($metadata -is [string]) { $metadata }
            else { $metadata | ConvertTo-Json -Compress }

            $row = [pscustomobject]@{
                tenant_id    = $fragmentTenant
                entity_type  = $EntityType
                entity_ref   = [string]$fragment.entity_ref
                title        = $fragment.title
                body         = $fragment.body
                summary      = $null
                source       = $fragment.source
                metadata     = $metadataJson
                content_hash = $null
            }
            $row.content_hash = Get-ImperionContentHash -InputObject @{ title = $row.title; body = $row.body }
            $row
        }

        $metricData = @{ $CountName = @($rows).Count }
        if ($LogData) {
            $extraData = & $LogData $entityRows
            if ($extraData) { foreach ($extraKey in $extraData.Keys) { $metricData[$extraKey] = $extraData[$extraKey] } }
        }
        Write-ImperionLog -Source 'knowledge' -Message "knowledge $LogLabel composed." -Data $metricData
        return @($rows)
    }
    finally { if ($ownsConnection) { $activeConnection.Dispose() } }
}
