#Requires -Modules Pester
# Cloud <-> local merge PARITY-PIN harness (issue #428) - generalizes the posture parity
# pin beyond posture. ADR-0026 dual-run convergence holds ONLY while the two copies of a
# merge stay in lockstep: both planes are "replace-from-source on the same source label",
# so a column one copy gains and the other lacks writes divergent silver with no test to
# catch it. This file is the single registry of every LP merge with a cloud Pipeline twin;
# for each pair it captures the LP merge SQL hermetically (mocked DB) and pins the
# fragments that must stay byte-equivalent to the twin, so drift fails CI, not prod.
#
# LP CI cannot read the sibling repo, so every pin is a LITERAL mirror of the twin's SQL,
# annotated with the cloud file + symbol it mirrors. If one side changes, change both AND
# this pin - that forced double-edit is the point.
#
# The registry (coverage guard enforces it below - a merge cmdlet whose help declares a
# twin with the phrase 'twin of the cloud' MUST be pinned here):
#   posture        <-> ImperionCRM_Pipeline src/shared/sync/posture-run.ts (runPostureRefresh)
#                      LIVE dual-run: cloud = on-demand account refresh, LP = scheduled bulk.
#   dns            <-> the account-scoped DNS on-demand refresh (ADR-0063 decision 2): the
#                      classification SQL is OWNED by Get-ImperionDnsDrift and reused
#                      verbatim by the cloud twin - pin the CASE + the dns_domain shape.
#   cloud_asset    <-> src/shared/merge-cloud-asset.ts as ceded (Pipeline #135 / PR #138).
#                      The cede contract: LP's copy must keep the agreed silver projection
#                      so a revived cloud copy (LP<->cloud parity: planes differ by TRIGGER,
#                      not capability) converges on the same rows.
#   m365_directory <-> src/shared/merge-directory.ts (mergeDirectoryGroups) as ceded
#                      (Pipeline #134 / PR #157). Same cede-contract pin.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force

    $script:publicRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\Public'

    # Every merge cmdlet parity-pinned by this harness. The coverage guard fails when a
    # merge cmdlet declares a cloud twin ('twin of the cloud') but is missing here.
    $script:pinnedTwinMerges = @(
        'Invoke-ImperionPostureMerge'
        'Invoke-ImperionDnsMerge'
        'Invoke-ImperionCloudAssetMerge'
        'Invoke-ImperionM365DirectoryMerge'
    )

    # Fake Npgsql connection: BeginTransaction for the PerTenant scaffold, Dispose no-op.
    $script:newFakeConnection = {
        $connection = [pscustomobject]@{ TransactionLog = [System.Collections.Generic.List[string]]::new() }
        $connection | Add-Member -MemberType ScriptMethod -Name BeginTransaction -Value {
            $tx = [pscustomobject]@{ Log = $this.TransactionLog }
            $tx | Add-Member -MemberType ScriptMethod -Name Commit -Value { $this.Log.Add('commit') }
            $tx | Add-Member -MemberType ScriptMethod -Name Rollback -Value { $this.Log.Add('rollback') }
            $tx | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
            $tx
        }
        $connection | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
        $connection
    }

    # Shared pin assertion: every fragment must appear byte-for-byte in the captured SQL.
    function Assert-ParityPin {
        param(
            [Parameter(Mandatory)][AllowEmptyString()][string] $Sql,
            [Parameter(Mandatory)][string[]] $Pin,
            [string] $Twin
        )
        foreach ($fragment in $Pin) {
            $Sql.Contains($fragment) |
                Should -BeTrue -Because "the merge SQL must stay byte-equivalent to $Twin - missing pinned fragment <$fragment>"
        }
    }
}

Describe 'Merge parity-pin harness (issue #428, ADR-0026 dual-run convergence)' {

    Context 'coverage guard - every declared cloud twin is pinned' {
        It 'pins every merge cmdlet whose help declares a cloud twin' {
            # The marker is the documented convention: a merge with a cloud twin says
            # 'twin of the cloud' in its help. New dual-run merge -> new registry entry
            # here, or this guard fails CI.
            $twinMerges = Get-ChildItem -Path $script:publicRoot -Recurse -Filter '*.ps1' |
                Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match 'twin of the cloud' } |
                ForEach-Object {
                    [regex]::Matches((Get-Content -LiteralPath $_.FullName -Raw),
                        'function\s+(Invoke-Imperion[A-Za-z0-9]+Merge)\b') |
                        ForEach-Object { $_.Groups[1].Value }
                }
            @($twinMerges | Sort-Object -Unique) | Should -Be @($script:pinnedTwinMerges | Sort-Object -Unique)
        }
    }

    # ── posture <-> posture-run.ts (LIVE dual-run) ─────────────────────────────────────
    Context 'posture - cloud twin posture-run.ts (runPostureRefresh), LIVE dual-run' {
        BeforeAll {
            $script:posture = InModuleScope ImperionPipeline -Parameters @{ makeConnection = $newFakeConnection } {
                param($makeConnection)
                Mock Write-ImperionLog { }
                Mock Invoke-ImperionDbQuery { @() }
                $script:parityCaptured = [System.Collections.Generic.List[pscustomobject]]::new()
                Mock Invoke-ImperionDbNonQuery {
                    $script:parityCaptured.Add([pscustomobject]@{ Sql = $Sql; Parameters = $Parameters }); 1
                }
                $conn = & $makeConnection
                Invoke-ImperionPostureMerge -TenantId 't-parity' -Connection $conn -Confirm:$false | Out-Null
                , $script:parityCaptured.ToArray()
            }
            $script:postureInserts = @($script:posture | Where-Object { $_.Sql -match 'INSERT INTO posture_policy' })
        }

        It 'classification CASE is byte-equivalent to reclassifyTenant (the original parity pin)' {
            $script:postureInserts.Count | Should -Be 5
            foreach ($statement in $script:postureInserts) {
                Assert-ParityPin -Sql $statement.Sql -Twin 'posture-run.ts reclassifyTenant' -Pin @(
                    "           WHEN g.policy_id   IS NULL THEN 'ungoverned'"
                    "           WHEN o.external_id IS NULL THEN 'missing'"
                    "           WHEN o.content_hash = g.golden_hash THEN 'compliant'"
                    "           ELSE 'drift'"
                )
            }
        }

        It 'projects the same posture_policy shape (columns, COALESCE ids, join key, ISO guard)' {
            foreach ($statement in $script:postureInserts) {
                Assert-ParityPin -Sql $statement.Sql -Twin 'posture-run.ts reclassifyTenant' -Pin @(
                    '    (tenant_id, policy_family, policy_id, policy_name, classification,'
                    '     observed_hash, golden_hash, observed_modified_at, golden_approved_at)'
                    '       COALESCE(o.external_id, g.policy_id),'
                    '       COALESCE(o.policy_name, g.policy_name),'
                    "       CASE WHEN o.modified_date_time ~ '^\d{4}-\d{2}-\d{2}'"
                    '            THEN o.modified_date_time::timestamptz END,'
                    '    ON g.tenant_id = o.tenant_id AND g.policy_id = o.external_id'
                    ' WHERE COALESCE(o.tenant_id, g.tenant_id) = @t'
                )
            }
        }

        It 'classifies exactly the POLICY_FAMILIES observed/golden pairs the cloud twin loops' {
            # Mirrors POLICY_FAMILIES in posture-run.ts - one insert per family against the
            # same observed/golden table pair. A family added on one side fails here.
            $expectedFamilies = @(
                @{ family = 'conditional_access'; observed = 'entra_conditional_access_policies'; golden = 'conditional_access_policies_golden' }
                @{ family = 'intune_security'; observed = 'intune_security_policies'; golden = 'intune_security_policies_golden' }
                @{ family = 'device_configuration'; observed = 'device_configuration_policies'; golden = 'device_configuration_policies_golden' }
                @{ family = 'autopilot'; observed = 'autopilot_policies'; golden = 'autopilot_policies_golden' }
                @{ family = 'defender_xdr'; observed = 'defender_xdr_security_policies'; golden = 'defender_xdr_security_policies_golden' }
            )
            @($script:postureInserts.Parameters.f | Sort-Object) |
                Should -Be @($expectedFamilies.family | Sort-Object)
            foreach ($expected in $expectedFamilies) {
                $statement = @($script:postureInserts | Where-Object { $_.Parameters.f -eq $expected.family })
                $statement.Count | Should -Be 1
                Assert-ParityPin -Sql $statement[0].Sql -Twin 'posture-run.ts POLICY_FAMILIES' -Pin @(
                    "  FROM `"$($expected.observed)`" o"
                    "  FULL OUTER JOIN `"$($expected.golden)`" g"
                )
            }
        }

        It 'replaces per tenant: DELETE then per-family inserts (replace-per-merge, never additive)' {
            $script:posture[0].Sql | Should -Be 'DELETE FROM posture_policy WHERE tenant_id = @t'
        }

        It 'tenant_posture rollup upserts the same column set ON CONFLICT (tenant_id)' {
            $rollup = @($script:posture | Where-Object { $_.Sql -match 'INSERT INTO tenant_posture' })
            $rollup.Count | Should -Be 1
            Assert-ParityPin -Sql $rollup[0].Sql -Twin 'posture-run.ts rollupTenant' -Pin @(
                '    (tenant_id, secure_score_current, secure_score_max, licensed_user_count,'
                '     active_user_count, policies_compliant, policies_drift, policies_ungoverned,'
                '     policies_missing, exposures_open, refreshed_at)'
                'ON CONFLICT (tenant_id) DO UPDATE SET'
                'EXCLUDED.secure_score_current'
                'EXCLUDED.secure_score_max'
                'EXCLUDED.licensed_user_count'
                'EXCLUDED.active_user_count'
                'EXCLUDED.policies_compliant'
                'EXCLUDED.policies_drift'
                'EXCLUDED.policies_ungoverned'
                'EXCLUDED.policies_missing'
                'EXCLUDED.exposures_open'
                "e.status <> 'resolved'"
                'ORDER BY collected_at DESC LIMIT 1'
                'JOIN account_tenant m ON m.account_id = e.account_id'
            )
        }
    }

    # ── dns <-> account-scoped DNS refresh (ADR-0063 decision 2) ───────────────────────
    Context 'dns - classification owned by Get-ImperionDnsDrift, reused verbatim by the cloud twin' {
        It 'record classification CASE mirrors the policy-drift parity CASE (four states, captured-vs-golden)' {
            $driftSql = InModuleScope ImperionPipeline -Parameters @{ makeConnection = $newFakeConnection } {
                param($makeConnection)
                Mock Write-ImperionLog { }
                $script:parityDriftSql = $null
                Mock Invoke-ImperionDbQuery { $script:parityDriftSql = $Sql; @() }
                Get-ImperionDnsDrift -Connection (& $makeConnection) | Out-Null
                $script:parityDriftSql
            }
            Assert-ParityPin -Sql $driftSql -Twin 'the cloud DNS refresh classification (ADR-0063 decision 2)' -Pin @(
                "               WHEN g.name IS NULL THEN 'ungoverned'"
                "               WHEN c.name IS NULL THEN 'missing'"
                "               WHEN c.content_hash = g.content_hash THEN 'compliant'"
                "               ELSE 'drift'"
                '      FULL OUTER JOIN captured_record c'
                '            AND c.record_type = g.record_type'
                '            AND c.name = g.name'
                # the three-state governance verdict ladder (ADR-0063 decision 3)
                "           WHEN az.in_azure IS NOT TRUE THEN 'not-in-azure'"
                "           WHEN az.manageable IS TRUE AND nd.domain IS NOT NULL THEN 'managed'"
                "           ELSE 'in-azure-readonly'"
            )
        }

        It 'dns_domain upsert pins the silver shape ON CONFLICT (tenant_id, domain)' {
            $upsertSql = InModuleScope ImperionPipeline -Parameters @{ makeConnection = $newFakeConnection } {
                param($makeConnection)
                Mock Write-ImperionLog { }
                Mock Get-ImperionDnsDrift {
                    @([pscustomobject]@{
                            domain = 'contoso.com'; account_id = 'acc-1'; verdict = 'managed'
                            records_compliant = 1; records_drift = 0; records_ungoverned = 0
                            records_missing = 0; score = 100; last_captured_at = '2026-06-30T00:00:00Z'
                        })
                }
                $script:parityDnsUpsert = $null
                Mock Invoke-ImperionDbNonQuery { $script:parityDnsUpsert = $Sql; 1 }
                Invoke-ImperionDnsMerge -Connection (& $makeConnection) -Confirm:$false | Out-Null
                $script:parityDnsUpsert
            }
            Assert-ParityPin -Sql $upsertSql -Twin 'the cloud DNS refresh dns_domain projection' -Pin @(
                'INSERT INTO dns_domain'
                '    (tenant_id, domain, account_id, verdict, records_compliant, records_drift,'
                '     records_ungoverned, records_missing, score, last_captured_at, refreshed_at)'
                'ON CONFLICT (tenant_id, domain) DO UPDATE SET'
                'EXCLUDED.account_id'
                'EXCLUDED.verdict'
                'EXCLUDED.records_compliant'
                'EXCLUDED.records_drift'
                'EXCLUDED.records_ungoverned'
                'EXCLUDED.records_missing'
                'EXCLUDED.score'
                'EXCLUDED.last_captured_at'
            )
        }
    }

    # ── cloud_asset <-> merge-cloud-asset.ts as ceded (Pipeline #135 / PR #138) ────────
    Context 'cloud_asset - cloud twin merge-cloud-asset.ts (mergeCloudAssetSources), cede contract' {
        BeforeAll {
            $script:cloudAsset = InModuleScope ImperionPipeline -Parameters @{ makeConnection = $newFakeConnection } {
                param($makeConnection)
                Mock Write-ImperionLog { }
                $script:parityReadSql = $null
                Mock Invoke-ImperionDbQuery {
                    $script:parityReadSql = $Sql
                    @([pscustomobject]@{
                            external_id = '/sub/1/vm-a'; name = 'vm-a'; type = 'Microsoft.Compute/virtualMachines'
                            location = 'eastus'; sku = 'Standard_D2'; resource_group = 'rg1'; subscription_id = 'sub1'
                            tags = '{}'; tenant_id = 't1'; source = 'azure_arm'
                            collected_at = '2026-06-18T00:00:00Z'; account_id = 'acc-1'
                        })
                }
                $script:parityUpsertSql = $null
                Mock Invoke-ImperionDbNonQuery { $script:parityUpsertSql = $Sql; 1 }
                Invoke-ImperionCloudAssetMerge -Connection (& $makeConnection) -Confirm:$false | Out-Null
                [pscustomobject]@{ ReadSql = $script:parityReadSql; UpsertSql = $script:parityUpsertSql }
            }
        }

        It 'reads bronze with the same account resolution (LEFT JOIN account_tenant, NULL kept)' {
            Assert-ParityPin -Sql $script:cloudAsset.ReadSql -Twin 'merge-cloud-asset.ts mergeCloudAssetSources' -Pin @(
                '  FROM cloud_resources cr'
                '  LEFT JOIN account_tenant at ON at.tenant_id = cr.tenant_id'
                'at.account_id::text AS account_id'
            )
        }

        It 'upserts the identical cloud_asset projection ON CONFLICT (provider, external_id)' {
            Assert-ParityPin -Sql $script:cloudAsset.UpsertSql -Twin 'merge-cloud-asset.ts upsertCloudAsset' -Pin @(
                'INSERT INTO cloud_asset ('
                '    provider, external_id, name, native_type, category, region, resource_group,'
                '    subscription_ref, sku, tags, tenant_id, source, account_id, last_seen_at'
                "    'azure', @external_id, @name, @native_type, @category::cloud_asset_category, @region, @resource_group,"
                '    @subscription_ref, @sku, @tags::jsonb, @tenant_id, @source, @account_id::uuid,'
                'ON CONFLICT (provider, external_id) DO UPDATE SET'
                'EXCLUDED.name'
                'EXCLUDED.native_type'
                'EXCLUDED.category'
                'EXCLUDED.region'
                'EXCLUDED.resource_group'
                'EXCLUDED.subscription_ref'
                'EXCLUDED.sku'
                'EXCLUDED.tags'
                'EXCLUDED.tenant_id'
                'EXCLUDED.source'
                'EXCLUDED.account_id'
                'EXCLUDED.last_seen_at'
                '    updated_at       = now()'
            )
        }

        It 'namespace-to-category map is byte-equivalent to NAMESPACE_CATEGORY (all 39 entries)' {
            # Pinned verbatim from the ceded merge-cloud-asset.ts NAMESPACE_CATEGORY.
            $expectedMap = [ordered]@{
                compute = 'compute'; containerservice = 'compute'; containerinstance = 'compute'
                containerregistry = 'compute'; batch = 'compute'
                storage = 'storage'; netapp = 'storage'
                network = 'network'; cdn = 'network'
                sql = 'database'; dbforpostgresql = 'database'; dbformysql = 'database'
                dbformariadb = 'database'; documentdb = 'database'; cache = 'database'
                managedidentity = 'identity'; aad = 'identity'; azureactivedirectory = 'identity'
                web = 'web'; appplatform = 'web'
                synapse = 'analytics'; datafactory = 'analytics'; databricks = 'analytics'
                kusto = 'analytics'; streamanalytics = 'analytics'; insights = 'analytics'
                servicebus = 'integration'; eventhub = 'integration'; eventgrid = 'integration'
                logic = 'integration'; apimanagement = 'integration'
                keyvault = 'security'; security = 'security'
                resources = 'management'; automation = 'management'; operationalinsights = 'management'
                recoveryservices = 'management'; portal = 'management'; management = 'management'
            }
            $expectedMap.Count | Should -Be 39
            InModuleScope ImperionPipeline -Parameters @{ map = $expectedMap } {
                param($map)
                foreach ($namespace in $map.Keys) {
                    ConvertTo-ImperionCloudAssetCategory -NativeType "Microsoft.$namespace/things" |
                        Should -Be $map[$namespace] -Because "namespace '$namespace' is pinned to NAMESPACE_CATEGORY in merge-cloud-asset.ts"
                }
            }
        }

        It 'normalizes exactly like normalizeCloudAssetCategory (case, prefix strip, other fallback)' {
            InModuleScope ImperionPipeline {
                ConvertTo-ImperionCloudAssetCategory -NativeType 'MICROSOFT.KEYVAULT/vaults' | Should -Be 'security'
                ConvertTo-ImperionCloudAssetCategory -NativeType 'network/foo' | Should -Be 'network'
                ConvertTo-ImperionCloudAssetCategory -NativeType 'Microsoft.Unknown/things' | Should -Be 'other'
                ConvertTo-ImperionCloudAssetCategory -NativeType '' | Should -Be 'other'
                ConvertTo-ImperionCloudAssetCategory -NativeType $null | Should -Be 'other'
            }
        }
    }

    # ── m365_directory <-> merge-directory.ts as ceded (Pipeline #134 / PR #157) ───────
    Context 'm365_directory - cloud twin merge-directory.ts (mergeDirectoryGroups), cede contract' {
        BeforeAll {
            $script:directory = InModuleScope ImperionPipeline -Parameters @{ makeConnection = $newFakeConnection } {
                param($makeConnection)
                Mock Write-ImperionLog { }
                $script:parityCaptured = [System.Collections.Generic.List[string]]::new()
                Mock Invoke-ImperionDbNonQuery { $script:parityCaptured.Add($Sql); 1 }
                Invoke-ImperionM365DirectoryMerge -Connection (& $makeConnection) -Confirm:$false | Out-Null
                , $script:parityCaptured.ToArray()
            }
        }

        It 'replace-from-source: clears ONLY the m365_directory facts before re-inserting' {
            # writeContactEnrichment's per-(contact, source) delete-then-insert, set-based:
            # the distinct source label is the idempotency key shared with the cloud twin.
            $script:directory[0] | Should -Be "DELETE FROM contact_enrichment WHERE source = 'm365_directory'"
        }

        It 'stamps the identical directory_groups fact (shape + provenance guardrail)' {
            $insertSql = @($script:directory | Where-Object { $_ -match 'INSERT INTO contact_enrichment' })
            $insertSql.Count | Should -Be 1
            Assert-ParityPin -Sql $insertSql[0] -Twin 'merge-directory.ts directoryFact/writeContactEnrichment' -Pin @(
                '    (contact_id, attribute_key, value_text, value_json, confidence, source, lawful_basis, observed_at, expires_at)'
                "       'directory_groups',"
                "       'm365_directory',"
                "       'legitimate_interest'::lawful_basis,"
                "               'id',   gm.group_external_id,"
                "               'name', coalesce(nullif(g.display_name, ''), gm.group_external_id)"
                "       CASE WHEN max(gm.collected_at) ~ '^\d{4}-\d{2}-\d{2}' THEN max(gm.collected_at)::timestamptz"
                '            ELSE now() END,'
            )
        }

        It 'pins the 0079 join contract + membership guards byte-equivalent to resolveContactGroups' {
            $insertSql = @($script:directory | Where-Object { $_ -match 'INSERT INTO contact_enrichment' })[0]
            Assert-ParityPin -Sql $insertSql -Twin 'merge-directory.ts resolveContactGroups' -Pin @(
                '  FROM m365_contacts c'
                '  JOIN m365_group_members gm'
                '        ON gm.member_external_id = c.external_ref'
                '  LEFT JOIN m365_groups g'
                '        ON g.tenant_id   = gm.tenant_id'
                '       AND g.external_id = gm.group_external_id'
                ' WHERE c.contact_id IS NOT NULL'
                '   AND c.external_ref IS NOT NULL'
                ' GROUP BY c.contact_id'
                'HAVING count(gm.group_external_id) FILTER (WHERE gm.group_external_id IS NOT NULL) > 0'
            )
        }
    }
}
