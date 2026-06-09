#Requires -Modules Pester
# Unit tests for the pure helpers (no external dependencies). Run: Invoke-Pester ./tests

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionContentHash' {
    It 'is stable regardless of property order' {
        $a = [pscustomobject]@{ b = 2; a = 1 }
        $b = [pscustomobject]@{ a = 1; b = 2 }
        ($a | Get-ImperionContentHash) | Should -Be ($b | Get-ImperionContentHash)
    }
    It 'ignores excluded volatile fields' {
        $a = [pscustomobject]@{ a = 1; collected_at = 'x' }
        $b = [pscustomobject]@{ a = 1; collected_at = 'y' }
        ($a | Get-ImperionContentHash) | Should -Be ($b | Get-ImperionContentHash)
    }
    It 'changes when a meaningful field changes' {
        $a = [pscustomobject]@{ a = 1 }
        $b = [pscustomobject]@{ a = 2 }
        ($a | Get-ImperionContentHash) | Should -Not -Be ($b | Get-ImperionContentHash)
    }
}

Describe 'ConvertTo-ImperionFlatObject' {
    It 'flattens with the standard envelope and a content hash' {
        $src = [pscustomobject]@{ id = '42'; displayName = 'Acme'; nested = [pscustomobject]@{ city = 'NYC' } }
        $map = [ordered]@{ name = 'displayName'; city = 'nested.city' }
        $row = $src | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'test' -TenantId 't1' -ExternalIdProperty 'id'

        $row.name        | Should -Be 'Acme'
        $row.city        | Should -Be 'NYC'
        $row.source      | Should -Be 'test'
        $row.tenant_id   | Should -Be 't1'
        $row.external_id | Should -Be '42'
        $row.content_hash | Should -Not -BeNullOrEmpty
        $row.raw_payload | Should -Match 'Acme'
    }
    It 'supports scriptblock selectors' {
        $src = [pscustomobject]@{ id = '1'; arr = @('a', 'b', 'c') }
        $map = [ordered]@{ joined = { param($x) $x.arr | Join-ImperionValues }; count = { param($x) @($x.arr).Count } }
        $row = $src | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'test' -TenantId 't1' -ExternalIdProperty 'id'
        $row.joined | Should -Be 'a; b; c'
        $row.count  | Should -Be 3
    }
}
