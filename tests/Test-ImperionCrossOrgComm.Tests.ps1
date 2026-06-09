#Requires -Modules Pester
# Unit tests for the private communication noise-control predicate Test-ImperionCrossOrgComm.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Test-ImperionCrossOrgComm' {
    Context 'ImperionTenant mode (collecting @imperionllc.com)' {
        It 'keeps a thread that includes a known client domain' {
            InModuleScope ImperionPipeline {
                Test-ImperionCrossOrgComm -Participant @('ada@imperionllc.com', 'sam@acme.com') -Mode ImperionTenant -ClientDomain @('acme.com', 'globex.com') | Should -BeTrue
            }
        }
        It 'drops an internal-only Imperion thread' {
            InModuleScope ImperionPipeline {
                Test-ImperionCrossOrgComm -Participant @('ada@imperionllc.com', 'bob@imperionllc.com') -Mode ImperionTenant -ClientDomain @('acme.com') | Should -BeFalse
            }
        }
        It 'drops a thread with a non-client external domain (e.g. a vendor)' {
            InModuleScope ImperionPipeline {
                Test-ImperionCrossOrgComm -Participant @('ada@imperionllc.com', 'rep@microsoft.com') -Mode ImperionTenant -ClientDomain @('acme.com') | Should -BeFalse
            }
        }
        It 'is case-insensitive on the client domain' {
            InModuleScope ImperionPipeline {
                Test-ImperionCrossOrgComm -Participant @('SAM@ACME.COM') -Mode ImperionTenant -ClientDomain @('acme.com') | Should -BeTrue
            }
        }
    }

    Context 'ClientTenant mode (collecting a customer tenant via GDAP)' {
        It 'keeps a thread that includes @imperionllc.com' {
            InModuleScope ImperionPipeline {
                Test-ImperionCrossOrgComm -Participant @('sam@acme.com', 'ada@imperionllc.com') -Mode ClientTenant | Should -BeTrue
            }
        }
        It 'drops a client-internal thread' {
            InModuleScope ImperionPipeline {
                Test-ImperionCrossOrgComm -Participant @('sam@acme.com', 'joe@acme.com') -Mode ClientTenant | Should -BeFalse
            }
        }
        It 'honors a custom ImperionDomain' {
            InModuleScope ImperionPipeline {
                Test-ImperionCrossOrgComm -Participant @('x@imperion.io') -Mode ClientTenant -ImperionDomain 'imperion.io' | Should -BeTrue
            }
        }
    }

    It 'ignores blank/invalid addresses without throwing' {
        InModuleScope ImperionPipeline {
            { Test-ImperionCrossOrgComm -Participant @($null, '', 'not-an-email', 'ada@imperionllc.com') -Mode ClientTenant } | Should -Not -Throw
            Test-ImperionCrossOrgComm -Participant @($null, '', 'not-an-email') -Mode ClientTenant | Should -BeFalse
        }
    }
}
