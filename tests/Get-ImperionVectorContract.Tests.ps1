#Requires -Modules Pester
# Get-ImperionVectorContract now reads the vendored copy of the front-end's single
# machine-readable home (front-end ADR-0102 / this repo's ADR-0025). These tests pin the
# projected values and the fail-loud behaviour; the CI drift guard
# (build/Test-VectorContractSync.ps1) separately verifies the vendored copy against canonical.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionVectorContract' {
    It 'projects the pinned contract (voyage-3-large / 1024 / v1) from the vendored home' {
        InModuleScope ImperionPipeline {
            $contract = Get-ImperionVectorContract
            $contract.EmbeddingModel      | Should -Be 'voyage-3-large'
            $contract.Dimension           | Should -Be 1024
            $contract.ChunkingVersion     | Should -Be 'v1'
            $contract.MaxChunkChars       | Should -Be 6000
            $contract.OverlapChars        | Should -Be 500
            $contract.ApiBatchSize        | Should -Be 64
            $contract.ApiBaseUri          | Should -Be 'https://api.voyageai.com/v1/embeddings'
            $contract.UsdPerMillionTokens | Should -Be 0.18
        }
    }

    It 'fails loud when the vendored contract file is absent' {
        InModuleScope ImperionPipeline {
            Mock Test-Path { $false }
            { Get-ImperionVectorContract } | Should -Throw '*vendored copy of the front-end home*'
        }
    }
}
