#Requires -Modules Pester
# Hermetic tests for Split-ImperionTextChunk: pure text chunking (chunking v1).
# Lever A (issue #226): Split-ImperionTextChunk is now a Private building block of
# Invoke-ImperionVectorizeKnowledge, so it is exercised in-module via InModuleScope
# rather than against the exported surface.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Split-ImperionTextChunk' {
    It 'returns nothing for empty / whitespace input' {
        InModuleScope ImperionPipeline {
            Split-ImperionTextChunk -Text ''     | Should -BeNullOrEmpty
            Split-ImperionTextChunk -Text '   '  | Should -BeNullOrEmpty
        }
    }

    It 'returns one trimmed chunk when the text fits' {
        InModuleScope ImperionPipeline {
            $chunks = @(Split-ImperionTextChunk -Text "  short body  ")
            $chunks.Count | Should -Be 1
            $chunks[0]    | Should -Be 'short body'
        }
    }

    It 'splits long text into multiple chunks no larger than MaxChars' {
        InModuleScope ImperionPipeline {
            $text = ('word ' * 2000).Trim()   # ~10,000 chars
            $chunks = @(Split-ImperionTextChunk -Text $text -MaxChars 3000 -OverlapChars 200)
            $chunks.Count | Should -BeGreaterThan 1
            foreach ($chunk in $chunks) { $chunk.Length | Should -BeLessOrEqual 3000 }
        }
    }

    It 'carries overlap so adjacent chunks share boundary context' {
        InModuleScope ImperionPipeline {
            $text = ('word ' * 2000).Trim()
            $chunks = @(Split-ImperionTextChunk -Text $text -MaxChars 3000 -OverlapChars 200)
            # The start of chunk 2 must appear inside chunk 1 (the overlap window).
            $chunks[0].Contains($chunks[1].Substring(0, 100)) | Should -BeTrue
        }
    }

    It 'prefers a paragraph boundary near the window end' {
        InModuleScope ImperionPipeline {
            $paragraphOne = 'a' * 2500
            $paragraphTwo = 'b' * 2500
            $chunks = @(Split-ImperionTextChunk -Text "$paragraphOne`n$paragraphTwo" -MaxChars 3000 -OverlapChars 0)
            # The first chunk should end exactly at the paragraph boundary, not mid-'b'.
            $chunks[0] | Should -Be $paragraphOne
        }
    }

    It 'is deterministic — same input, same chunks' {
        InModuleScope ImperionPipeline {
            $text = ('lorem ipsum dolor sit amet. ' * 500).Trim()
            $first  = @(Split-ImperionTextChunk -Text $text -MaxChars 2000)
            $second = @(Split-ImperionTextChunk -Text $text -MaxChars 2000)
            ($first -join '|') | Should -Be ($second -join '|')
        }
    }
}
