#Requires -Modules Pester
# Hermetic tests for Get-ImperionKnowledgeDevice: DB layer mocked per query shape.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Get-ImperionKnowledgeDevice' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock Get-ImperionConfig { @{ LocalTenantId = 'tenant-1' } }
            Mock Write-ImperionLog {}
            # Route the composer's two inventory arms by their FROM clause.
            Mock Invoke-ImperionDbQuery {
                if ($Sql -match 'FROM device d') {
                    return @([pscustomobject]@{
                        id = 'dev-1'; name = 'FS01'; device_type = 'server'; manufacturer = 'Dell'
                        model = 'PowerEdge R750'; serial_number = 'SN123'; os = 'Windows Server 2022'
                        status = 'active'; last_seen = '2026-06-01'; account_name = 'Acme Corp'
                        origin = 'local-pipeline'
                    })
                }
                if ($Sql -match 'FROM itglue_export_configurations') {
                    return @([pscustomobject]@{
                        id = 'cfg-9'; name = 'ACME-LT-042'; device_type = 'Laptop'; manufacturer = 'Lenovo'
                        model = 'T14'; serial_number = 'SN999'; os = 'Windows 11'
                        status = 'Active'; last_seen = '2026-06-05'; account_name = 'Acme Corp'
                        origin = 'itglue'
                    })
                }
                return @()
            }
        }
    }

    It 'composes one knowledge_object row per device across both inventory arms' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionKnowledgeDevice -Connection ([pscustomobject]@{}))
            $rows.Count             | Should -Be 2
            $rows[0].entity_type    | Should -Be 'device'
            $rows[0].entity_ref     | Should -Be 'dev-1'
            $rows[0].title          | Should -Be 'FS01'
            $rows[0].tenant_id      | Should -Be 'tenant-1'
            $rows[0].source         | Should -Be 'local-pipeline'
            $rows[1].entity_ref     | Should -Be 'cfg-9'
            $rows[1].source         | Should -Be 'itglue'
        }
    }

    It 'writes the device facts and inventory origin into the body text' {
        InModuleScope ImperionPipeline {
            $rows = @(Get-ImperionKnowledgeDevice -Connection ([pscustomobject]@{}))
            $rows[0].body | Should -Match 'Device: FS01'
            $rows[0].body | Should -Match 'Account: Acme Corp'
            $rows[0].body | Should -Match 'serial: SN123'
            $rows[0].body | Should -Match 'unified silver device record'
            $rows[1].body | Should -Match 'IT Glue configuration \(not yet merged to silver\)'
        }
    }

    It 'has the knowledge metadata shape and a stable content hash' {
        InModuleScope ImperionPipeline {
            $first  = @(Get-ImperionKnowledgeDevice -Connection ([pscustomobject]@{}))[0]
            $second = @(Get-ImperionKnowledgeDevice -Connection ([pscustomobject]@{}))[0]
            $first.content_hash | Should -Match '^[0-9a-f]{64}$'
            $first.content_hash | Should -Be $second.content_hash
            $metadata = $first.metadata | ConvertFrom-Json
            $metadata.account     | Should -Be 'Acme Corp'
            $metadata.device_type | Should -Be 'server'
            $metadata.origin      | Should -Be 'local-pipeline'
        }
    }

    It 'returns nothing (and does not throw) when both arms are empty' {
        InModuleScope ImperionPipeline {
            Mock Invoke-ImperionDbQuery { @() }
            @(Get-ImperionKnowledgeDevice -Connection ([pscustomobject]@{})) | Should -BeNullOrEmpty
        }
    }
}
