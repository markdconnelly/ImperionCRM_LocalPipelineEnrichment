#Requires -Modules Pester
# Unit tests for Join-ImperionValues (pure flat-table value flattener).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Join-ImperionValues' {
    It 'joins a piped array with the default delimiter' {
        @('a', 'b', 'c') | Join-ImperionValues | Should -Be 'a; b; c'
    }

    It 'joins an array passed by -Value (not unrolled per element)' {
        Join-ImperionValues -Value @('a', 'b') | Should -Be 'a; b'
    }

    It 'honors a custom delimiter' {
        @('a', 'b') | Join-ImperionValues -Delimiter ',' | Should -Be 'a,b'
    }

    It 'passes a single scalar through as its string form' {
        'solo' | Join-ImperionValues | Should -Be 'solo'
        42 | Join-ImperionValues | Should -Be '42'
    }

    It 'treats a string as one value, not a character sequence' {
        'hello' | Join-ImperionValues | Should -Be 'hello'
    }

    It 'returns $null for null or empty input' {
        ($null | Join-ImperionValues) | Should -BeNullOrEmpty
        (@() | Join-ImperionValues) | Should -BeNullOrEmpty
    }
}
