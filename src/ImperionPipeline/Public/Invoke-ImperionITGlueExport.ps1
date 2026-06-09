function Invoke-ImperionITGlueExport {
    <#
    .SYNOPSIS
        Export the entire IT Glue dataset into Postgres, with relationships in the polymorphic edge table.
    .DESCRIPTION
        Per type: page the collection, flatten to a generic envelope, upsert into itglue_<type>
        with change detection; write each record's relationships into itglue_relationship
        (delete-then-insert so re-runs converge). Secrets/passwords are not exported (ADR-0006).
        Requires Initialize-ImperionContext.
    .EXAMPLE
        Invoke-ImperionITGlueExport
    #>
    [CmdletBinding()]
    param()

    $cfg = Get-ImperionConfig
    $names = Get-ImperionSecretNames
    $started = Get-Date
    $apiKey = Get-ImperionSecretValue -Name $names.ITGlueReadKey
    $base = $cfg.ITGlue.BaseUri

    $resourceTypes = @(
        @{ Path = 'organizations';            Table = 'itglue_organizations' }
        @{ Path = 'configurations';           Table = 'itglue_configurations' }
        @{ Path = 'contacts';                 Table = 'itglue_contacts' }
        @{ Path = 'locations';                Table = 'itglue_locations' }
        @{ Path = 'flexible_asset_types';     Table = 'itglue_flexible_asset_types' }
        @{ Path = 'domains';                  Table = 'itglue_domains' }
        @{ Path = 'manufacturers';            Table = 'itglue_manufacturers' }
        @{ Path = 'models';                   Table = 'itglue_models' }
        @{ Path = 'operating_systems';        Table = 'itglue_operating_systems' }
        @{ Path = 'configuration_types';      Table = 'itglue_configuration_types' }
        @{ Path = 'organization_types';       Table = 'itglue_organization_types' }
        @{ Path = 'organization_statuses';    Table = 'itglue_organization_statuses' }
    )

    function Get-Attr { param($obj, [string]$name) $p = $obj.PSObject.Properties[$name]; if ($p) { $p.Value } else { $null } }

    function ConvertTo-ItGlueRow {
        param($rec)
        $attrs = $rec.attributes
        $row = [pscustomobject][ordered]@{
            source          = 'itglue'
            external_id     = [string]$rec.id
            organization_id = [string](Get-Attr $attrs 'organization-id')
            name            = [string](Get-Attr $attrs 'name')
            resource_url    = [string](Get-Attr $attrs 'resource-url')
            created_at      = [string](Get-Attr $attrs 'created-at')
            updated_at      = [string](Get-Attr $attrs 'updated-at')
            collected_at    = (Get-Date).ToString('o')
            raw_payload     = ($attrs | ConvertTo-Json -Compress -Depth 30)
        }
        $row | Add-Member -NotePropertyName content_hash -NotePropertyValue ($row | Get-ImperionContentHash -ExcludeProperty collected_at, content_hash, raw_payload) -PassThru
    }

    function Save-Relationships {
        param($Connection, $rec)
        $rels = $rec.PSObject.Properties['relationships']
        if (-not $rels -or -not $rels.Value) { return 0 }
        $fromType = [string]$rec.type; $fromId = [string]$rec.id
        Invoke-ImperionDbNonQuery -Connection $Connection -Sql 'DELETE FROM itglue_relationship WHERE from_type=@ft AND from_id=@fi' -Parameters @{ ft = $fromType; fi = $fromId } | Out-Null
        $edgeCount = 0
        foreach ($relName in $rels.Value.PSObject.Properties.Name) {
            $data = $rels.Value.$relName.data
            if (-not $data) { continue }
            foreach ($target in @($data)) {
                if (-not $target.id) { continue }
                Invoke-ImperionDbNonQuery -Connection $Connection -Sql @'
INSERT INTO itglue_relationship (from_type, from_id, to_type, to_id, relationship_name)
VALUES (@ft, @fi, @tt, @ti, @rn) ON CONFLICT DO NOTHING
'@ -Parameters @{ ft = $fromType; fi = $fromId; tt = [string]$target.type; ti = [string]$target.id; rn = $relName } | Out-Null
                $edgeCount++
            }
        }
        return $edgeCount
    }

    $conn = New-ImperionDbConnection
    try {
        foreach ($rt in $resourceTypes) {
            $records = Invoke-ImperionITGlueRequest -Path $rt.Path -ApiKey $apiKey -Query 'sort=-updated-at&page[size]=1000' -BaseUri $base
            $rows = @($records | ForEach-Object { ConvertTo-ItGlueRow $_ })
            $edges = 0
            foreach ($r in $records) { $edges += (Save-Relationships -Connection $conn -rec $r) }
            $tally = if ($rows.Count) { Invoke-ImperionBronzeUpsert -Connection $conn -Table $rt.Table -Rows $rows -KeyColumns @('source', 'external_id') } else { [pscustomobject]@{ scanned = 0; inserted = 0; updated = 0; unchanged = 0 } }
            Write-ImperionLog -Level Metric -Source 'itglue' -Message "$($rt.Table) exported." -Data @{ scanned = $tally.scanned; inserted = $tally.inserted; updated = $tally.updated; unchanged = $tally.unchanged; edges = $edges }
        }

        $fatRecords = Invoke-ImperionITGlueRequest -Path 'flexible_asset_types' -ApiKey $apiKey -Query 'page[size]=1000' -BaseUri $base
        foreach ($fat in $fatRecords) {
            $assets = Invoke-ImperionITGlueRequest -Path 'flexible_assets' -ApiKey $apiKey -Query ("filter[flexible_asset_type_id]={0}&page[size]=1000" -f $fat.id) -BaseUri $base
            $rows = @($assets | ForEach-Object { ConvertTo-ItGlueRow $_ })
            $edges = 0
            foreach ($a in $assets) { $edges += (Save-Relationships -Connection $conn -rec $a) }
            if ($rows.Count) {
                $tally = Invoke-ImperionBronzeUpsert -Connection $conn -Table 'itglue_flexible_assets' -Rows $rows -KeyColumns @('source', 'external_id')
                Write-ImperionLog -Level Metric -Source 'itglue' -Message "itglue_flexible_assets (type $($fat.attributes.name)) exported." -Data @{ scanned = $tally.scanned; inserted = $tally.inserted; updated = $tally.updated; unchanged = $tally.unchanged; edges = $edges }
            }
        }
    }
    finally { $conn.Dispose() }

    Write-ImperionLog -Level Metric -Source 'itglue' -Message 'IT Glue export complete.' -Data @{ seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 1) }
}
