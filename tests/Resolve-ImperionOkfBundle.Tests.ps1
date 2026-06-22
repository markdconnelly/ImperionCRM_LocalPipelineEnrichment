#Requires -Modules Pester
# Hermetic tests for Resolve-ImperionOkfBundle: the -BundlePath branch needs no git/network.
# Proves the 'ok' / 'no-bundle' resolution and that a caller-supplied path is never cleaned up.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Resolve-ImperionOkfBundle' {
    It "returns Reason 'ok' with the tables path and no cleanup when -BundlePath has a tables dir" {
        InModuleScope ImperionPipeline {
            $root = Join-Path ([System.IO.Path]::GetTempPath()) ("imperion-okf-res-{0}" -f ([guid]::NewGuid().ToString('N')))
            New-Item -ItemType Directory -Force -Path (Join-Path $root 'tables') | Out-Null
            try {
                $resolved = Resolve-ImperionOkfBundle -BundlePath $root
                $resolved.Reason     | Should -Be 'ok'
                $resolved.BundlePath | Should -Be $root
                $resolved.TablesPath | Should -Be (Join-Path $root 'tables')
                $resolved.Cleanup    | Should -BeNullOrEmpty   # caller-supplied path is never removed
            }
            finally { Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue }
        }
    }

    It "returns Reason 'no-bundle' when -BundlePath has no tables dir" {
        InModuleScope ImperionPipeline {
            $root = Join-Path ([System.IO.Path]::GetTempPath()) ("imperion-okf-res-{0}" -f ([guid]::NewGuid().ToString('N')))
            New-Item -ItemType Directory -Force -Path $root | Out-Null
            try {
                $resolved = Resolve-ImperionOkfBundle -BundlePath $root
                $resolved.Reason     | Should -Be 'no-bundle'
                $resolved.TablesPath | Should -BeNullOrEmpty
                $resolved.Cleanup    | Should -BeNullOrEmpty
            }
            finally { Remove-Item -Recurse -Force $root -ErrorAction SilentlyContinue }
        }
    }
}
