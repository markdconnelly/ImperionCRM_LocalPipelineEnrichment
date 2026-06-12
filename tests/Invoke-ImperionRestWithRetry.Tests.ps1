#Requires -Modules Pester
# Hermetic tests for the retry/backoff policy Invoke-ImperionRestWithRetry. The transport helper
# Invoke-ImperionHttp is mocked (normal return value); Start-Sleep is mocked so backoff is instant.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionRestWithRetry' {
    It 'returns the response on a 2xx without retrying' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionHttp { [pscustomobject]@{ Body = [pscustomobject]@{ value = 'ok' }; Status = 200; Headers = @{} } }
            $r = Invoke-ImperionRestWithRetry -Uri 'https://x/y'
            $r.Status | Should -Be 200
            $r.Body.value | Should -Be 'ok'
            Should -Invoke Invoke-ImperionHttp -Times 1
        }
    }

    It 'retries on 429 honoring Retry-After, then returns the success' {
        InModuleScope ImperionPipeline {
            Mock Start-Sleep { }
            Mock Write-ImperionLog { }
            $script:n = 0
            Mock Invoke-ImperionHttp {
                $script:n++
                if ($script:n -eq 1) { [pscustomobject]@{ Body = $null; Status = 429; Headers = @{ 'Retry-After' = @('1') } } }
                else { [pscustomobject]@{ Body = [pscustomobject]@{ value = 'recovered' }; Status = 200; Headers = @{} } }
            }
            $r = Invoke-ImperionRestWithRetry -Uri 'https://x/y'
            $r.Body.value | Should -Be 'recovered'
            Should -Invoke Invoke-ImperionHttp -Times 2
            Should -Invoke Start-Sleep -Times 1 -ParameterFilter { $Seconds -eq 1 }
        }
    }

    It 'uses exponential backoff when no Retry-After header is present' {
        InModuleScope ImperionPipeline {
            Mock Start-Sleep { }
            Mock Write-ImperionLog { }
            $script:m = 0
            Mock Invoke-ImperionHttp {
                $script:m++
                if ($script:m -eq 1) { [pscustomobject]@{ Body = $null; Status = 503; Headers = @{} } }
                else { [pscustomobject]@{ Body = 'ok'; Status = 200; Headers = @{} } }
            }
            Invoke-ImperionRestWithRetry -Uri 'https://x/y' | Out-Null
            Should -Invoke Start-Sleep -Times 1 -ParameterFilter { $Seconds -eq 2 }   # 2^attempt (attempt 1)
        }
    }

    It 'throws immediately on a non-retryable 4xx' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionHttp { [pscustomobject]@{ Body = [pscustomobject]@{ error = 'nope' }; Status = 404; Headers = @{} } }
            { Invoke-ImperionRestWithRetry -Uri 'https://x/y' } | Should -Throw '*HTTP 404*'
            Should -Invoke Invoke-ImperionHttp -Times 1
        }
    }

    It 'redacts apikey-style querystring secrets from error text (issue #98 secret-bearing URLs)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionHttp { [pscustomobject]@{ Body = $null; Status = 404; Headers = @{} } }
            $thrown = $null
            try { Invoke-ImperionRestWithRetry -Uri 'https://x/v1/quote?page=1&apikey=SuperSecret123' }
            catch { $thrown = $_.Exception.Message }
            $thrown | Should -Not -Match 'SuperSecret123'
            $thrown | Should -Match 'apikey=REDACTED'
        }
    }

    It 'redacts the secret from throttle log lines too' {
        InModuleScope ImperionPipeline {
            Mock Start-Sleep { }
            $script:loggedMessages = [System.Collections.Generic.List[string]]::new()
            Mock Write-ImperionLog { $script:loggedMessages.Add($Message) }
            $script:r = 0
            Mock Invoke-ImperionHttp {
                $script:r++
                if ($script:r -eq 1) { [pscustomobject]@{ Body = $null; Status = 429; Headers = @{ 'Retry-After' = @('1') } } }
                else { [pscustomobject]@{ Body = 'ok'; Status = 200; Headers = @{} } }
            }
            Invoke-ImperionRestWithRetry -Uri 'https://x/v1/quote?apikey=SuperSecret123' | Out-Null
            ($script:loggedMessages -join "`n") | Should -Not -Match 'SuperSecret123'
            ($script:loggedMessages -join "`n") | Should -Match 'apikey=REDACTED'
        }
    }

    It 'retries up to MaxAttempts then throws the final HTTP status on persistent 503' {
        InModuleScope ImperionPipeline {
            Mock Start-Sleep { }
            Mock Write-ImperionLog { }
            Mock Invoke-ImperionHttp { [pscustomobject]@{ Body = $null; Status = 503; Headers = @{} } }
            { Invoke-ImperionRestWithRetry -Uri 'https://x/y' -MaxAttempts 3 } | Should -Throw '*HTTP 503*'
            Should -Invoke Invoke-ImperionHttp -Times 3   # 2 retries + the final attempt that throws
            Should -Invoke Start-Sleep -Times 2
        }
    }
}
