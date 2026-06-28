#Requires -Modules Pester
# Hermetic tests for Get-ImperionDattoRmmDevice: Datto RMM request + key resolver mocked.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionDattoRmmDevice' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'partner' } }
            Mock Resolve-ImperionDattoRmmApiKey { 'resolved-key' }
        }
    }

    It 'flattens a device to the datto_rmm_devices envelope (source datto_rmm, external_id = uid)' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDattoRmmRequest {
                , @([pscustomobject]@{
                        uid              = 'DEV-1'
                        hostname         = 'WS-01'
                        siteName         = 'Acme HQ'
                        operatingSystem  = 'Windows 11 Pro'
                        lastSeen         = '2026-06-14T12:00:00Z'
                        patchManagement  = [pscustomobject]@{ patchStatus = 'UpToDate' }
                        antivirus        = [pscustomobject]@{ antivirusStatus = 'Running' }
                        agentVersion     = '4.2.0'
                        deviceType       = [pscustomobject]@{ category = 'Desktop' }
                        softDelete       = $false
                    })
            }
            $rows = @(Get-ImperionDattoRmmDevice)
            $rows.Count | Should -Be 1
            $rows[0].device_uid       | Should -Be 'DEV-1'
            $rows[0].hostname         | Should -Be 'WS-01'
            $rows[0].site_name        | Should -Be 'Acme HQ'
            $rows[0].operating_system | Should -Be 'Windows 11 Pro'
            $rows[0].patch_status     | Should -Be 'UpToDate'
            $rows[0].antivirus_status | Should -Be 'Running'
            $rows[0].agent_version    | Should -Be '4.2.0'
            $rows[0].device_type      | Should -Be 'Desktop'
            $rows[0].source           | Should -Be 'datto_rmm'
            $rows[0].tenant_id        | Should -Be 'partner'
            $rows[0].external_id      | Should -Be 'DEV-1'
            $rows[0].content_hash     | Should -Not -BeNullOrEmpty
        }
    }

    It 'survives unknown field names: flat columns land null, raw_payload keeps everything' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDattoRmmRequest { , @([pscustomobject]@{ uid = 'DEV-9'; surpriseField = 'x' }) }
            $rows = @(Get-ImperionDattoRmmDevice)
            $rows[0].patch_status | Should -BeNullOrEmpty
            $rows[0].hostname     | Should -BeNullOrEmpty
            $rows[0].external_id  | Should -Be 'DEV-9'
            $rows[0].raw_payload  | Should -Match 'surpriseField'
        }
    }

    It 'resolves the MSP-wide key via Resolve-ImperionDattoRmmApiKey and passes it to the connect layer' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDattoRmmRequest { , @() }
            Get-ImperionDattoRmmDevice | Out-Null
            Should -Invoke Resolve-ImperionDattoRmmApiKey -Times 1
            Should -Invoke Invoke-ImperionDattoRmmRequest -Times 1 -ParameterFilter {
                $ApiKey -eq 'resolved-key' -and $EntityProperty -eq 'devices'
            }
        }
    }
}
