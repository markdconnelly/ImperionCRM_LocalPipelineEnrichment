#Requires -Modules Pester
# Hermetic tests for the Invoke-ImperionDnsZoneSync orchestrator: per-subscription isolation
# (#339) — one subscription's dnsZones failure must not abort the whole sweep.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Invoke-ImperionDnsZoneSync' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Write-ImperionLog {}
            Mock Get-ImperionAzureSubscription {
                @([pscustomobject]@{ external_id = 'sub-bad' }, [pscustomobject]@{ external_id = 'sub-good' })
            }
            Mock Set-ImperionDnsZoneToBronze {}
        }
    }

    It 'isolates a per-subscription failure and still collects the others (#339)' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionDnsZoneObject {
                if ($SubscriptionId -eq 'sub-bad') { throw 'HTTP 400 calling GET .../dnsZones' }
                [pscustomobject]@{ entity = 'zones'; domain = 'ok.com' }
            }
            { Invoke-ImperionDnsZoneSync } | Should -Not -Throw
            # The good subscription still flowed to bronze...
            Should -Invoke Set-ImperionDnsZoneToBronze -Times 1 -Exactly
            # ...and the bad one logged a per-subscription Warn (not an aborting sweep-level skip).
            Should -Invoke Write-ImperionLog -ParameterFilter {
                $Level -eq 'Warn' -and $Message -match "subscription 'sub-bad'"
            }
        }
    }

    It 'logs and exits cleanly when subscription enumeration itself fails' {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionAzureSubscription { throw 'migration 0080 not applied' }
            Mock Get-ImperionDnsZoneObject { throw 'should not be reached' }
            { Invoke-ImperionDnsZoneSync } | Should -Not -Throw
            Should -Invoke Get-ImperionDnsZoneObject -Times 0 -Exactly
            Should -Invoke Write-ImperionLog -ParameterFilter {
                $Level -eq 'Warn' -and $Message -match 'Azure DNS posture sync skipped'
            }
        }
    }
}
