#Requires -Modules Pester
# Hermetic tests for Get-ImperionPlaudRecording: secrets + MCP calls mocked.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionPlaudRecording' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'partner' } }
            Mock Get-ImperionSecretNames { @{ PlaudOAuthToken = 'plaud-oauth-token' } }
            Mock Get-ImperionSecretValue { 'raw-token' }
            Mock Write-ImperionLog {}
            Mock Invoke-ImperionPlaudRequest {
                switch ($Tool) {
                    'list_files' { [pscustomobject]@{ files = @([pscustomobject]@{ id = 'f1'; title = 'Acme kickoff'; startedAt = '2026-06-10T15:00:00Z'; duration = 1800 }) } }
                    'get_note' { [pscustomobject]@{ summary = 'Agreed rollout plan.'; actionItems = @('Send SOW', 'Book follow-up') } }
                    'get_transcript' { [pscustomobject]@{ text = 'Mark: hello. Jane: hi.' } }
                }
            }
        }
    }

    It 'composes one flat bronze row per recording (note + transcript merged in)' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionPlaudRecording)
            $rows.Count                | Should -Be 1
            $rows[0].external_id       | Should -Be 'f1'
            $rows[0].title             | Should -Be 'Acme kickoff'
            $rows[0].duration_seconds  | Should -Be '1800'
            $rows[0].summary           | Should -Be 'Agreed rollout plan.'
            $rows[0].action_items      | Should -Be 'Send SOW; Book follow-up'
            $rows[0].transcript        | Should -Be 'Mark: hello. Jane: hi.'
            $rows[0].source            | Should -Be 'plaud'
            $rows[0].tenant_id         | Should -Be 'partner'
            $rows[0].content_hash      | Should -Match '^[0-9a-f]{64}$'
        }
    }

    It 'skips the transcript call with -SkipTranscript' {
        InModuleScope ImperionPipeline {
            @(Get-ImperionPlaudRecording -SkipTranscript) | Out-Null
            Should -Invoke Invoke-ImperionPlaudRequest -Times 0 -ParameterFilter { $Tool -eq 'get_transcript' }
        }
    }

    It 'unwraps a JSON token blob (access_token field)' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionSecretValue { '{"access_token":"blob-token","refresh_token":"r"}' }
            @(Get-ImperionPlaudRecording -SkipTranscript) | Out-Null
            Should -Invoke Invoke-ImperionPlaudRequest -ParameterFilter { $AccessToken -eq 'blob-token' }
        }
    }

    It 'returns nothing (and does not throw) when list_files is empty' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionPlaudRequest { [pscustomobject]@{ files = @() } }
            @(Get-ImperionPlaudRecording) | Should -BeNullOrEmpty
        }
    }

    It 'lets an auth failure throw (the task layer owns the log-and-skip gate)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionPlaudRequest { throw 'Plaud MCP tool ''list_files'' failed: unauthorized (code -32001)' }
            { Get-ImperionPlaudRecording } | Should -Throw '*unauthorized*'
        }
    }
}
