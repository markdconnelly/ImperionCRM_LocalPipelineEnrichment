#Requires -Modules Pester
# Hermetic unit tests for the threads post-layer writers (adapters over Invoke-ImperionBronzePost).
# Asserts each projects to its exact migration-0208 column set and routes to the right table.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionThreadsPostToBronze' {
    BeforeEach {
        InModuleScope ImperionPipeline { Mock Write-ImperionLog { } }
    }

    It 'projects rows to the migration-0208 threads_posts column set and upserts' {
        InModuleScope ImperionPipeline {
            $captured = @{}
            Mock Invoke-ImperionBronzeUpsert { $captured.Table = $Table; $captured.Rows = $Rows; [pscustomobject]@{ scanned = 1; inserted = 1; updated = 0; unchanged = 0 } }
            $row = [pscustomobject]@{
                threads_user_id = 'u1'; username = 'imperion'; text_content = 'hi'; media_type = 'TEXT_POST'
                permalink = 'p'; shortcode = 'sc'; is_quote_post = 'false'; reply_audience = 'everyone'; created_time = 'c'
                tenant_id = 't1'; source = 'threads'; external_id = '1'; collected_at = 'now'; raw_payload = '{}'; content_hash = 'h'
                strayCollectorField = 'dropped-from-flat'
            }
            $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            $tally = $row | Set-ImperionThreadsPostToBronze -Connection $conn
            $tally.inserted | Should -Be 1
            $captured.Table | Should -Be 'threads_posts'
            $captured.Rows[0].threads_user_id | Should -Be 'u1'
            $captured.Rows[0].reply_audience | Should -Be 'everyone'
            $captured.Rows[0].PSObject.Properties.Name | Should -Not -Contain 'strayCollectorField'
        }
    }

    It 'returns the zero tally on empty input without touching the database' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionBronzeUpsert { }
            $tally = @() | Set-ImperionThreadsPostToBronze
            $tally.scanned | Should -Be 0
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }

    It 'honors -WhatIf (no upsert)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionBronzeUpsert { }
            $row = [pscustomobject]@{ text_content = 'm'; tenant_id = 't'; source = 'threads'; external_id = '1'; collected_at = 'n'; raw_payload = '{}'; content_hash = 'h' }
            $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            $row | Set-ImperionThreadsPostToBronze -Connection $conn -WhatIf | Out-Null
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}

Describe 'threads writer table routing + exact 0208 column sets' {
    BeforeEach {
        InModuleScope ImperionPipeline { Mock Write-ImperionLog { } }
    }

    It '<writer> targets <table> with column set <columns>' -ForEach @(
        @{ writer = 'Set-ImperionThreadsPostToBronze'; table = 'threads_posts'
            columns = @('threads_user_id', 'username', 'text_content', 'media_type', 'permalink', 'shortcode', 'is_quote_post', 'reply_audience', 'created_time', 'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash') }
        @{ writer = 'Set-ImperionThreadsReplyToBronze'; table = 'threads_replies'
            columns = @('root_post_external_id', 'replied_to_external_id', 'threads_user_id', 'username', 'text_content', 'media_type', 'permalink', 'hide_status', 'created_time', 'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash') }
        @{ writer = 'Set-ImperionThreadsMentionToBronze'; table = 'threads_mentions'
            columns = @('mentioned_post_external_id', 'threads_user_id', 'username', 'text_content', 'permalink', 'created_time', 'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash') }
        @{ writer = 'Set-ImperionThreadsInsightToBronze'; table = 'threads_insights'
            columns = @('entity_kind', 'entity_external_id', 'metric', 'period', 'end_time', 'value', 'tenant_id', 'source', 'external_id', 'collected_at', 'raw_payload', 'content_hash') }
    ) {
        $parameters = @{ writer = $writer; table = $table; columns = $columns }
        InModuleScope ImperionPipeline -Parameters $parameters {
            $captured = @{}
            Mock Invoke-ImperionBronzePost { $captured.Table = $Table; $captured.ColumnSet = $ColumnSet; [pscustomobject]@{ scanned = 0 } }
            $row = [pscustomobject]@{ tenant_id = 't'; source = 'threads'; external_id = '1'; collected_at = 'n'; raw_payload = '{}'; content_hash = 'h' }
            $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            $row | & $writer -Connection $conn | Out-Null
            $captured.Table | Should -Be $table
            ($captured.ColumnSet -join ',') | Should -Be ($columns -join ',')
        }
    }
}
