#Requires -Modules Pester
# Hermetic unit tests for the credential-blob field extractor (issue #299): the conn-company-*
# secrets are JSON blobs (backend setSecret(name, JSON.stringify(fields))); this pulls one field
# out, passes bare strings through untouched, and throws loudly on a malformed blob.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'ConvertFrom-ImperionCredentialBlob' {

    It 'extracts the named field from a JSON object blob' {
        InModuleScope ImperionPipeline {
            ConvertFrom-ImperionCredentialBlob -Value '{"apiKey":"abc123","region":"us"}' -Field 'apiKey' |
                Should -Be 'abc123'
        }
    }

    It 'tolerates leading whitespace before the JSON object' {
        InModuleScope ImperionPipeline {
            ConvertFrom-ImperionCredentialBlob -Value "  {`"apiKey`":`"spaced`"}" -Field 'apiKey' |
                Should -Be 'spaced'
        }
    }

    It 'returns a bare-string secret unchanged' {
        InModuleScope ImperionPipeline {
            ConvertFrom-ImperionCredentialBlob -Value 'a-plain-api-key' -Field 'apiKey' |
                Should -Be 'a-plain-api-key'
        }
    }

    It 'returns an empty value unchanged' {
        InModuleScope ImperionPipeline {
            ConvertFrom-ImperionCredentialBlob -Value '' -Field 'apiKey' | Should -Be ''
        }
    }

    It 'treats a non-JSON value that happens to start with a brace as a bare string' {
        InModuleScope ImperionPipeline {
            ConvertFrom-ImperionCredentialBlob -Value '{not really json' -Field 'apiKey' |
                Should -Be '{not really json'
        }
    }

    It 'throws an actionable error when the blob lacks the field' {
        InModuleScope ImperionPipeline {
            { ConvertFrom-ImperionCredentialBlob -Value '{"region":"us"}' -Field 'apiKey' } |
                Should -Throw -ExpectedMessage "*missing the 'apiKey' field*"
        }
    }

    It 'throws when the field is present but empty' {
        InModuleScope ImperionPipeline {
            { ConvertFrom-ImperionCredentialBlob -Value '{"apiKey":""}' -Field 'apiKey' } |
                Should -Throw -ExpectedMessage "*missing the 'apiKey' field*"
        }
    }
}
