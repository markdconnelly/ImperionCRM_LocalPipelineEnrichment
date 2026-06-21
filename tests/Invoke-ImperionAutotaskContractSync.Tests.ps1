#Requires -Modules Pester
# Hermetic tests for Invoke-ImperionAutotaskContractSync: get + post layers mocked.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionAutotaskContractSync' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionAutotaskContract { , @([pscustomobject]@{ external_id = '1' }) }
            Mock Set-ImperionAutotaskContractToBronze { [pscustomobject]@{ scanned = 1; inserted = 1; updated = 0; unchanged = 0 } }
            Mock Write-ImperionLog {}
        }
        Remove-Item Env:IMPERION_AUTOTASK_CONTRACT_SINCE_DAYS -ErrorAction SilentlyContinue
    }
    AfterEach {
        Remove-Item Env:IMPERION_AUTOTASK_CONTRACT_SINCE_DAYS -ErrorAction SilentlyContinue
    }

    It 'pipes the collector into the bronze writer and returns the tally' {
        InModuleScope ImperionPipeline {
            $tally = Invoke-ImperionAutotaskContractSync
            $tally.inserted | Should -Be 1
            Should -Invoke Get-ImperionAutotaskContract -Times 1
            Should -Invoke Set-ImperionAutotaskContractToBronze -Times 1
        }
    }

    It 'defaults the window to 7 days when neither parameter nor env var is set' {
        InModuleScope ImperionPipeline {
            Invoke-ImperionAutotaskContractSync | Out-Null
            Should -Invoke Get-ImperionAutotaskContract -Times 1 -ParameterFilter { $SinceDays -eq 7 }
        }
    }

    It 'honors IMPERION_AUTOTASK_CONTRACT_SINCE_DAYS when no parameter is given' {
        $env:IMPERION_AUTOTASK_CONTRACT_SINCE_DAYS = '30'
        InModuleScope ImperionPipeline {
            Invoke-ImperionAutotaskContractSync | Out-Null
            Should -Invoke Get-ImperionAutotaskContract -Times 1 -ParameterFilter { $SinceDays -eq 30 }
        }
    }

    It 'lets an explicit -SinceDays 0 request a full backfill (overriding the env var)' {
        $env:IMPERION_AUTOTASK_CONTRACT_SINCE_DAYS = '30'
        InModuleScope ImperionPipeline {
            Invoke-ImperionAutotaskContractSync -SinceDays 0 | Out-Null
            Should -Invoke Get-ImperionAutotaskContract -Times 1 -ParameterFilter { $SinceDays -eq 0 }
        }
    }
}
