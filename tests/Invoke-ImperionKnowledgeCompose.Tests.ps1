#Requires -Modules Pester
# Hermetic tests for Invoke-ImperionKnowledgeCompose (the knowledge-composer spine, #106/#111):
# DB layer mocked.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionKnowledgeCompose' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ PartnerTenantId = 'partner-tenant' } }
            Mock Write-ImperionLog {}
        }
    }

    It 'emits the full knowledge_object row shape from a minimal compose fragment' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { @([pscustomobject]@{ id = '7'; name = 'Acme' }) }
            $rows = @(Invoke-ImperionKnowledgeCompose -EntityType 'account' -Connection ([pscustomobject]@{}) `
                    -Query 'SELECT 1' -Compose {
                    param($entityRow)
                    [pscustomobject]@{
                        entity_ref = $entityRow.id; title = $entityRow.name
                        body = "Account: $($entityRow.name)"; source = 'local-pipeline'
                        metadata = @{ contacts = 0 }
                    }
                })
            $rows.Count           | Should -Be 1
            $rows[0].tenant_id    | Should -Be 'partner-tenant'
            $rows[0].entity_type  | Should -Be 'account'
            $rows[0].entity_ref   | Should -Be '7'
            $rows[0].title        | Should -Be 'Acme'
            $rows[0].body         | Should -Be 'Account: Acme'
            $rows[0].summary      | Should -BeNullOrEmpty
            $rows[0].source       | Should -Be 'local-pipeline'
            $rows[0].metadata     | Should -Be '{"contacts":0}'
            $rows[0].content_hash | Should -Match '^[0-9a-f]{64}$'
        }
    }

    It 'content_hash matches Get-ImperionContentHash over title+body (idempotency contract)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { @([pscustomobject]@{ id = '1' }) }
            $rows = @(Invoke-ImperionKnowledgeCompose -EntityType 'ticket' -Connection ([pscustomobject]@{}) `
                    -Query 'SELECT 1' -Compose {
                    [pscustomobject]@{ entity_ref = '1'; title = 'T'; body = 'B'; source = 'autotask'; metadata = @{} }
                })
            $rows[0].content_hash | Should -Be (Get-ImperionContentHash -InputObject @{ title = 'T'; body = 'B' })
        }
    }

    It 'logs the empty message and returns nothing when the primary query is empty' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { @() }
            $rows = @(Invoke-ImperionKnowledgeCompose -EntityType 'contact' -Connection ([pscustomobject]@{}) `
                    -Query 'SELECT 1' -EmptyMessage 'knowledge contacts: no silver contacts found.' -Compose { throw 'never' })
            $rows | Should -BeNullOrEmpty
            Should -Invoke Write-ImperionLog -Times 1 -Exactly -ParameterFilter {
                $Message -eq 'knowledge contacts: no silver contacts found.'
            }
        }
    }

    It 'groups related queries into per-key lookup caches the compose block can read' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery {
                if ($Sql -match 'FROM account') {
                    @([pscustomobject]@{ id = 'a1'; name = 'Acme' }, [pscustomobject]@{ id = 'a2'; name = 'Beta' })
                }
                else {
                    @(
                        [pscustomobject]@{ account_id = 'a1'; full_name = 'Jane' }
                        [pscustomobject]@{ account_id = 'a1'; full_name = 'Joe' }
                    )
                }
            }
            $rows = @(Invoke-ImperionKnowledgeCompose -EntityType 'account' -Connection ([pscustomobject]@{}) `
                    -Query 'SELECT ... FROM account' `
                    -RelatedQueries @{ contacts = @{ Sql = 'SELECT ... FROM contact'; KeyColumn = 'account_id' } } `
                    -Compose {
                    param($account, $related)
                    $accountContacts = if ($related['contacts'].ContainsKey($account.id)) { $related['contacts'][$account.id] } else { @() }
                    [pscustomobject]@{
                        entity_ref = $account.id; title = $account.name
                        body = "contacts: $(@($accountContacts).Count)"; source = 'local-pipeline'
                        metadata = @{ contacts = @($accountContacts).Count }
                    }
                })
            $rows.Count   | Should -Be 2
            $rows[0].body | Should -Be 'contacts: 2'
            $rows[1].body | Should -Be 'contacts: 0'
            # Related query ran once, not per entity row.
            Should -Invoke Invoke-ImperionDbQuery -Times 2 -Exactly
        }
    }

    It 'accepts a scriptblock -Query receiving the open connection' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { throw 'spine must not run SQL for a scriptblock query' }
            $marker = [pscustomobject]@{ tag = 'conn' }
            $rows = @(Invoke-ImperionKnowledgeCompose -EntityType 'device' -Connection $marker `
                    -Query { param($connection) $connection.tag | Should -Be 'conn'; @([pscustomobject]@{ id = 'd1' }) } `
                    -Compose {
                    [pscustomobject]@{ entity_ref = 'd1'; title = 'D'; body = 'B'; source = 'itglue'; metadata = @{} }
                })
            $rows.Count | Should -Be 1
        }
    }

    It 'skips rows whose compose block returns nothing' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { @([pscustomobject]@{ id = '1' }, [pscustomobject]@{ id = '2' }) }
            $rows = @(Invoke-ImperionKnowledgeCompose -EntityType 'proposal' -Connection ([pscustomobject]@{}) `
                    -Query 'SELECT 1' -Compose {
                    param($entityRow)
                    if ($entityRow.id -eq '2') { return $null }
                    [pscustomobject]@{ entity_ref = $entityRow.id; title = 'P'; body = 'B'; source = 'local-pipeline'; metadata = @{} }
                })
            $rows.Count         | Should -Be 1
            $rows[0].entity_ref | Should -Be '1'
        }
    }

    Context '-PerRowTenant (posture-style composers)' {
        It 'stamps each row with the tenant the compose block returns and never defaults' {
            InModuleScope ImperionPipeline {
                Mock Get-ImperionConfig { throw 'spine must not read config under -PerRowTenant' }
                Mock Invoke-ImperionDbQuery { @([pscustomobject]@{ tenant_id = 't-1' }, [pscustomobject]@{ tenant_id = 't-2' }) }
                $rows = @(Invoke-ImperionKnowledgeCompose -EntityType 'posture' -PerRowTenant -Connection ([pscustomobject]@{}) `
                        -Query 'SELECT 1' -LogLabel 'posture' -CountName 'tenants' -Compose {
                        param($tenantRow)
                        [pscustomobject]@{
                            tenant_id = $tenantRow.tenant_id; entity_ref = $tenantRow.tenant_id
                            title = "posture $($tenantRow.tenant_id)"; body = 'B'; source = 'local-pipeline'; metadata = @{}
                        }
                    })
                $rows.Count        | Should -Be 2
                $rows[0].tenant_id | Should -Be 't-1'
                $rows[1].tenant_id | Should -Be 't-2'
            }
        }

        It 'throws when a fragment carries no tenant_id' {
            InModuleScope ImperionPipeline {
                Mock Invoke-ImperionDbQuery { @([pscustomobject]@{ tenant_id = 't-1' }) }
                {
                    Invoke-ImperionKnowledgeCompose -EntityType 'posture' -PerRowTenant -Connection ([pscustomobject]@{}) `
                        -Query 'SELECT 1' -Compose {
                        [pscustomobject]@{ entity_ref = 'x'; title = 'T'; body = 'B'; source = 's'; metadata = @{} }
                    }
                } | Should -Throw '*requires every composed fragment to carry tenant_id*'
            }
        }
    }

    It 'merges -LogData extras into the final metric log' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery {
                @([pscustomobject]@{ id = '1'; origin = 'itglue' }, [pscustomobject]@{ id = '2'; origin = 'local-pipeline' })
            }
            @(Invoke-ImperionKnowledgeCompose -EntityType 'device' -Connection ([pscustomobject]@{}) `
                    -Query 'SELECT 1' `
                    -LogData { param($entityRows) @{ itglue = @($entityRows | Where-Object { $_.origin -eq 'itglue' }).Count } } `
                    -Compose {
                    param($entityRow)
                    [pscustomobject]@{ entity_ref = $entityRow.id; title = 'D'; body = 'B'; source = $entityRow.origin; metadata = @{} }
                }) | Out-Null
            Should -Invoke Write-ImperionLog -Times 1 -Exactly -ParameterFilter {
                $Message -eq 'knowledge devices composed.' -and $Data.devices -eq 2 -and $Data.itglue -eq 1
            }
        }
    }

    It 'opens and disposes its own connection when none is passed' {
        InModuleScope ImperionPipeline {
            $script:disposed = $false
            Mock New-ImperionDbConnection {
                $connection = [pscustomobject]@{}
                $connection | Add-Member -MemberType ScriptMethod -Name Dispose -Value { $script:disposed = $true }
                $connection
            }
            Mock Invoke-ImperionDbQuery { @([pscustomobject]@{ id = '1' }) }
            @(Invoke-ImperionKnowledgeCompose -EntityType 'contract' -Query 'SELECT 1' -Compose {
                    [pscustomobject]@{ entity_ref = '1'; title = 'C'; body = 'B'; source = 'autotask'; metadata = @{} }
                }) | Out-Null
            Should -Invoke New-ImperionDbConnection -Times 1 -Exactly
            $script:disposed | Should -BeTrue
        }
    }

    It 'passes a pre-serialized metadata string through unchanged' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { @([pscustomobject]@{ id = '1' }) }
            $rows = @(Invoke-ImperionKnowledgeCompose -EntityType 'exposure' -Connection ([pscustomobject]@{}) `
                    -Query 'SELECT 1' -Compose {
                    [pscustomobject]@{ entity_ref = '1'; title = 'E'; body = 'B'; source = 'darkwebid'; metadata = '{"a":1}' }
                })
            $rows[0].metadata | Should -Be '{"a":1}'
        }
    }
}
