#Requires -Modules Pester
# Hermetic tests for Register-ImperionTask. The ScheduledTasks cmdlets are mocked. Assertions use
# -WhatIf and the pre-ShouldProcess builders (New-ScheduledTaskAction): the real
# Register-ScheduledTask strictly type-checks its -Action (CimInstance) even when mocked, so we
# verify task composition without reaching the registration call.

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force
}

Describe 'Register-ImperionTask' {
    BeforeEach {
        InModuleScope ImperionPipeline {
            Mock New-ScheduledTaskPrincipal { 'principal' }
            Mock New-ScheduledTaskSettingsSet { 'settings' }
            Mock New-ScheduledTaskAction { 'action' }
            Mock New-ScheduledTaskTrigger { 'trigger' }
            Mock Invoke-ImperionTaskRegistration { }
            Mock Register-ScheduledTask { }
            Mock Write-Host { }
        }
    }

    It 'builds one task action per sync cmdlet and registers nothing under -WhatIf' {
        InModuleScope ImperionPipeline {
            Register-ImperionTask -TaskIdentity 'CORP\svc-imperion$' -PwshPath 'C:\pwsh\pwsh.exe' -WhatIf
            Should -Invoke New-ScheduledTaskAction -Times 12
            Should -Invoke Invoke-ImperionTaskRegistration -Times 0
        }
    }

    It 'schedules the knowledge + vectorization sync after the ingest tasks (ADR-0009)' {
        InModuleScope ImperionPipeline {
            Register-ImperionTask -TaskIdentity 'CORP\svc-imperion$' -PwshPath 'C:\pwsh\pwsh.exe' -WhatIf
            Should -Invoke New-ScheduledTaskAction -ParameterFilter {
                $Argument -match 'Invoke-ImperionKnowledgeSync -Vectorize'
            }
        }
    }

    It 'embeds Import-Module + Initialize-ImperionContext + the cmdlet in the task action' {
        InModuleScope ImperionPipeline {
            Register-ImperionTask -TaskIdentity 'CORP\svc-imperion$' -PwshPath 'C:\pwsh\pwsh.exe' -WhatIf
            Should -Invoke New-ScheduledTaskAction -ParameterFilter {
                $Argument -match 'Import-Module ImperionPipeline' -and $Argument -match 'Initialize-ImperionContext' -and $Argument -match 'Invoke-ImperionServicePrincipalSync'
            }
        }
    }

    It 'runs each task under the supplied gMSA/service identity' {
        InModuleScope ImperionPipeline {
            Register-ImperionTask -TaskIdentity 'CORP\svc-imperion$' -PwshPath 'C:\pwsh\pwsh.exe' -WhatIf
            Should -Invoke New-ScheduledTaskPrincipal -ParameterFilter { $UserId -eq 'CORP\svc-imperion$' }
        }
    }

    It 'gMSA mode registers a principal and never a credential (no stored password)' {
        InModuleScope ImperionPipeline {
            Register-ImperionTask -TaskIdentity 'CORP\svc-imperion$' -PwshPath 'C:\pwsh\pwsh.exe'
            Should -Invoke Invoke-ImperionTaskRegistration -Times 12
            Should -Invoke Invoke-ImperionTaskRegistration -Times 0 -Exactly -ParameterFilter {
                $null -ne $Credential
            }
        }
    }

    It 'local-account mode (ADR-0012) registers stored credentials and skips the principal' {
        InModuleScope ImperionPipeline {
            $secret = ConvertTo-SecureString 'test-only-password' -AsPlainText -Force
            $credential = [pscredential]::new('.\svc-imperion', $secret)

            Register-ImperionTask -TaskCredential $credential -PwshPath 'C:\pwsh\pwsh.exe'

            Should -Invoke New-ScheduledTaskPrincipal -Times 0 -Exactly
            Should -Invoke Invoke-ImperionTaskRegistration -Times 12 -ParameterFilter {
                $Credential.UserName -eq '.\svc-imperion' -and $null -eq $Principal
            }
            # the password never leaks into the task action command line
            Should -Invoke New-ScheduledTaskAction -Times 0 -Exactly -ParameterFilter {
                $Argument -match 'test-only-password'
            }
        }
    }

    It 'TaskIdentity and TaskCredential are mutually exclusive parameter sets' {
        InModuleScope ImperionPipeline {
            $secret = ConvertTo-SecureString 'test-only-password' -AsPlainText -Force
            $credential = [pscredential]::new('.\svc-imperion', $secret)
            {
                Register-ImperionTask -TaskIdentity 'CORP\svc-imperion$' -TaskCredential $credential `
                    -PwshPath 'C:\pwsh\pwsh.exe'
            } | Should -Throw
        }
    }

    It 'throws when pwsh cannot be resolved' {
        InModuleScope ImperionPipeline {
            { Register-ImperionTask -TaskIdentity 'CORP\svc-imperion$' -PwshPath '' } | Should -Throw '*pwsh.exe not found*'
        }
    }

    It 'reports "Registered" only on success — a failed task warns, never prints Registered (#246)' {
        InModuleScope ImperionPipeline {
            Mock Write-Warning { }
            Mock Invoke-ImperionTaskRegistration { throw 'No mapping between account names and security IDs was done.' }
            $secret = ConvertTo-SecureString 'test-only-password' -AsPlainText -Force
            $credential = [pscredential]::new('.\svc-imperion', $secret)

            Register-ImperionTask -TaskCredential $credential -PwshPath 'C:\pwsh\pwsh.exe'

            # every task failed → not one "Registered" line, and each surfaced a warning
            Should -Invoke Write-Host -Times 0 -Exactly -ParameterFilter { $Object -match '^Registered ' }
            Should -Invoke Write-Warning -Times 12 -ParameterFilter { $Message -match 'Failed to register' }
        }
    }
}

Describe 'Resolve-ImperionLocalTaskUser (#246 — SID-resolvable -User)' {
    It 'qualifies a .\local account with the machine name' {
        InModuleScope ImperionPipeline {
            Resolve-ImperionLocalTaskUser -UserName '.\svc-imperion' | Should -Be "$env:COMPUTERNAME\svc-imperion"
        }
    }
    It 'qualifies a bare local account name' {
        InModuleScope ImperionPipeline {
            Resolve-ImperionLocalTaskUser -UserName 'svc-imperion' | Should -Be "$env:COMPUTERNAME\svc-imperion"
        }
    }
    It 'leaves an already-qualified DOMAIN\name untouched' {
        InModuleScope ImperionPipeline {
            Resolve-ImperionLocalTaskUser -UserName 'CORP\svc-imperion' | Should -Be 'CORP\svc-imperion'
        }
    }
    It 'leaves a gMSA principal and a UPN untouched' {
        InModuleScope ImperionPipeline {
            Resolve-ImperionLocalTaskUser -UserName 'CORP\svc-imperion$' | Should -Be 'CORP\svc-imperion$'
            Resolve-ImperionLocalTaskUser -UserName 'svc@corp.example' | Should -Be 'svc@corp.example'
        }
    }
}
