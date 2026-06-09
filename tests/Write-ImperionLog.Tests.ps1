#Requires -Modules Pester
# Tests for Write-ImperionLog. The log directory is redirected to TestDrive via the
# IMPERION_LOG_DIR env var so a real JSONL line is written and parsed back.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Write-ImperionLog' {
    BeforeEach { $env:IMPERION_LOG_DIR = "$TestDrive\logs" }
    AfterEach { Remove-Item Env:\IMPERION_LOG_DIR -ErrorAction SilentlyContinue }

    It 'appends a structured JSON line with run fields and merged data' {
        Write-ImperionLog -Level Metric -Source 'm365' -Message 'sync complete' -Data @{ scanned = 5; updated = 2 } -RunId 'run-123'
        $file = Get-ChildItem -Path "$TestDrive\logs" -Filter 'imperion-*.jsonl' | Select-Object -First 1
        $file | Should -Not -BeNullOrEmpty
        $rec = Get-Content $file.FullName | Select-Object -Last 1 | ConvertFrom-Json
        $rec.level   | Should -Be 'Metric'
        $rec.source  | Should -Be 'm365'
        $rec.message | Should -Be 'sync complete'
        $rec.runId   | Should -Be 'run-123'
        $rec.scanned | Should -Be 5
        $rec.updated | Should -Be 2
        $rec.ts      | Should -Not -BeNullOrEmpty
    }

    It 'defaults level to Info and source to pipeline' {
        Write-ImperionLog -Message 'hello'
        $file = Get-ChildItem -Path "$TestDrive\logs" -Filter 'imperion-*.jsonl' | Select-Object -First 1
        $rec = Get-Content $file.FullName | Select-Object -Last 1 | ConvertFrom-Json
        $rec.level  | Should -Be 'Info'
        $rec.source | Should -Be 'pipeline'
    }

    It 'creates the log directory if it does not exist' {
        $fresh = "$TestDrive\logs-create-test"   # a path no other test touches (TestDrive is shared per-Describe)
        $env:IMPERION_LOG_DIR = $fresh
        Test-Path $fresh | Should -BeFalse
        Write-ImperionLog -Message 'create me'
        Test-Path $fresh | Should -BeTrue
    }
}
