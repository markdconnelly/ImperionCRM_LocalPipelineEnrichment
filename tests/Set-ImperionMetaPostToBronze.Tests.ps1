#Requires -Modules Pester
# Hermetic unit tests for the meta post-layer writers (adapters over Invoke-ImperionBronzePost).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Set-ImperionMetaPostToBronze' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            Mock Write-ImperionLog { }
        }
    }

    It 'projects rows to the migration-0075 facebook_posts column set and upserts' {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            $captured = @{}
            Mock Invoke-ImperionBronzeUpsert { $captured.Table = $Table; $captured.Rows = $Rows; [pscustomobject]@{ scanned = 1; inserted = 1; updated = 0; unchanged = 0 } }
            $row = [pscustomobject]@{
                page_id = 'pg'; message = 'm'; story = $null; status_type = 's'; permalink_url = 'u'
                from_id = 'f'; from_name = 'n'; created_time = 'c'; updated_time = 'u2'
                is_published = 'true'; comment_count = '1'; reaction_count = '2'; share_count = '3'
                tenant_id = 't1'; source = 'facebook'; external_id = 'p1'; collected_at = 'now'; raw_payload = '{}'; content_hash = 'h'
                strayCollectorField = 'dropped-from-flat'
            }
            $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            $tally = $row | Set-ImperionMetaPostToBronze -Connection $conn
            $tally.inserted | Should -Be 1
            $captured.Table | Should -Be 'facebook_posts'
            $captured.Rows[0].page_id | Should -Be 'pg'
            $captured.Rows[0].share_count | Should -Be '3'
            $captured.Rows[0].PSObject.Properties.Name | Should -Not -Contain 'strayCollectorField'
        }
    }

    It 'returns the zero tally on empty input without touching the database' {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            Mock Invoke-ImperionBronzeUpsert { }
            $tally = @() | Set-ImperionMetaPostToBronze
            $tally.scanned | Should -Be 0
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }

    It 'honors -WhatIf (no upsert)' {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            Mock Invoke-ImperionBronzeUpsert { }
            $row = [pscustomobject]@{ message = 'm'; tenant_id = 't'; source = 'facebook'; external_id = '1'; collected_at = 'n'; raw_payload = '{}'; content_hash = 'h' }
            $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            $row | Set-ImperionMetaPostToBronze -Connection $conn -WhatIf | Out-Null
            Should -Invoke Invoke-ImperionBronzeUpsert -Times 0
        }
    }
}

Describe 'meta writer table routing' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            Mock Write-ImperionLog { }
        }
    }

    It '<writer> targets <table>' -ForEach @(
        @{ writer = 'Set-ImperionMetaCommentToBronze'; table = 'facebook_comments' }
        @{ writer = 'Set-ImperionMetaMessageToBronze'; table = 'facebook_messages' }
        @{ writer = 'Set-ImperionInstagramMediaToBronze'; table = 'instagram_media' }
        @{ writer = 'Set-ImperionInstagramCommentToBronze'; table = 'instagram_comments' }
        @{ writer = 'Set-ImperionMetaInsightToBronze'; table = 'meta_insights' }
    ) {
        $parameters = @{ writer = $writer; table = $table }
        InModuleScope ImperionPipeline -Parameters $parameters {
            Mock Assert-ImperionColumnSet { }   # drift guard is unit-tested on its own (#427)
            $captured = @{}
            Mock Invoke-ImperionBronzeUpsert { $captured.Table = $Table; [pscustomobject]@{ scanned = 1; inserted = 1; updated = 0; unchanged = 0 } }
            $row = [pscustomobject]@{ tenant_id = 't'; source = 's'; external_id = '1'; collected_at = 'n'; raw_payload = '{}'; content_hash = 'h' }
            $conn = [pscustomobject]@{} | Add-Member -PassThru -MemberType ScriptMethod -Name Dispose -Value { }
            $row | & $writer -Connection $conn | Out-Null
            $captured.Table | Should -Be $table
        }
    }
}
