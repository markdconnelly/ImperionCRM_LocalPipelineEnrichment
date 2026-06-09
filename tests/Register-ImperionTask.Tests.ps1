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
            Mock Register-ScheduledTask { }
            Mock Write-Host { }
        }
    }

    It 'builds one task action per sync cmdlet and registers nothing under -WhatIf' {
        InModuleScope ImperionPipeline {
            Register-ImperionTask -TaskIdentity 'CORP\svc-imperion$' -PwshPath 'C:\pwsh\pwsh.exe' -WhatIf
            Should -Invoke New-ScheduledTaskAction -Times 6
            Should -Invoke Register-ScheduledTask -Times 0
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

    It 'throws when pwsh cannot be resolved' {
        InModuleScope ImperionPipeline {
            { Register-ImperionTask -TaskIdentity 'CORP\svc-imperion$' -PwshPath '' } | Should -Throw '*pwsh.exe not found*'
        }
    }
}
