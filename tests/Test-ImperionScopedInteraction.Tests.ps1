#Requires -Modules Pester
# Unit tests for the private scope predicate Test-ImperionScopedInteraction (pure, no I/O).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
    InModuleScope ImperionPipeline {
        function script:New-Set {
            param([string[]]$Values = @())
            $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($v in $Values) { [void]$set.Add($v) }
            , $set
        }
    }
}

Describe 'Test-ImperionScopedInteraction' {
    It 'keeps a thread with an allowlisted principal AND a client-domain counterpart' {
        InModuleScope ImperionPipeline {
            Test-ImperionScopedInteraction -Participant @('derek@imperionllc.com', 'sam@acme.com') `
                -AllowedPrincipal @('derek@imperionllc.com') -ClientEmail (New-Set) -ClientDomain (New-Set @('acme.com')) |
                Should -BeTrue
        }
    }

    It 'keeps a thread matched by exact client-contact email even if the domain is not listed' {
        InModuleScope ImperionPipeline {
            Test-ImperionScopedInteraction -Participant @('mark@imperionllc.com', 'cfo@globex.com') `
                -AllowedPrincipal @('mark@imperionllc.com') -ClientEmail (New-Set @('cfo@globex.com')) -ClientDomain (New-Set) |
                Should -BeTrue
        }
    }

    It 'drops an internal-only Imperion thread (no client counterpart)' {
        InModuleScope ImperionPipeline {
            Test-ImperionScopedInteraction -Participant @('derek@imperionllc.com', 'mark@imperionllc.com') `
                -AllowedPrincipal @('derek@imperionllc.com', 'mark@imperionllc.com') -ClientEmail (New-Set) -ClientDomain (New-Set @('acme.com')) |
                Should -BeFalse
        }
    }

    It 'drops a thread with a non-client external party (vendor) and no client counterpart' {
        InModuleScope ImperionPipeline {
            Test-ImperionScopedInteraction -Participant @('derek@imperionllc.com', 'rep@microsoft.com') `
                -AllowedPrincipal @('derek@imperionllc.com') -ClientEmail (New-Set) -ClientDomain (New-Set @('acme.com')) |
                Should -BeFalse
        }
    }

    It 'drops a client thread when NO allowlisted principal is involved (non-allowlisted employee)' {
        InModuleScope ImperionPipeline {
            Test-ImperionScopedInteraction -Participant @('intern@imperionllc.com', 'sam@acme.com') `
                -AllowedPrincipal @('derek@imperionllc.com') -ClientEmail (New-Set) -ClientDomain (New-Set @('acme.com')) |
                Should -BeFalse
        }
    }

    It 'returns false when the allowlist is empty' {
        InModuleScope ImperionPipeline {
            Test-ImperionScopedInteraction -Participant @('derek@imperionllc.com', 'sam@acme.com') `
                -AllowedPrincipal @() -ClientEmail (New-Set) -ClientDomain (New-Set @('acme.com')) |
                Should -BeFalse
        }
    }

    It 'is case-insensitive on principal and client domain' {
        InModuleScope ImperionPipeline {
            Test-ImperionScopedInteraction -Participant @('DEREK@IMPERIONLLC.COM', 'SAM@ACME.COM') `
                -AllowedPrincipal @('derek@imperionllc.com') -ClientEmail (New-Set) -ClientDomain (New-Set @('acme.com')) |
                Should -BeTrue
        }
    }

    It 'does not let an allowlisted principal double-count as its own client counterpart' {
        InModuleScope ImperionPipeline {
            # Only the two principals present; even though one principal address is (wrongly) in the
            # client set, a principal cannot satisfy both halves alone.
            Test-ImperionScopedInteraction -Participant @('derek@imperionllc.com', 'mark@imperionllc.com') `
                -AllowedPrincipal @('derek@imperionllc.com', 'mark@imperionllc.com') `
                -ClientEmail (New-Set @('derek@imperionllc.com')) -ClientDomain (New-Set) |
                Should -BeFalse
        }
    }

    It 'ignores blank/invalid addresses without throwing' {
        InModuleScope ImperionPipeline {
            { Test-ImperionScopedInteraction -Participant @($null, '', 'not-an-email', 'derek@imperionllc.com', 'sam@acme.com') `
                    -AllowedPrincipal @('derek@imperionllc.com') -ClientEmail (New-Set) -ClientDomain (New-Set @('acme.com')) } | Should -Not -Throw
        }
    }
}
