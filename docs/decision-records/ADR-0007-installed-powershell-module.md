# ADR-0007: Package as an installed PowerShell module (not a folder of scripts)

| Field | Value |
|---|---|
| **Repo** | local-pipeline |
| **Status** | Accepted |
| **Date** | 2026-06-08 |
| **Deciders** | Mark (human), Claude Code |
| **Cross-references** | — |

## Problem

The first cut was a repo of standalone scripts that dot-sourced a `_bootstrap.ps1`. Mark
wants this delivered as a **full PowerShell module installed on the PC**, so operations run
as `Import-Module ImperionPipeline; <cmdlet>` and scheduled tasks call cmdlets by name.

## Options considered

None recorded in the original ADR.

## Decision

Ship **`ImperionPipeline`** as a versioned, installable module:
- Each former entry script is now an **exported advanced function (cmdlet)**:
  `Invoke-ImperionServicePrincipalSync`, `Invoke-ImperionAzureInventorySync`,
  `Invoke-ImperionSecureScoreSync`, `Invoke-ImperionPolicySync`,
  `Invoke-ImperionITGlueExport`, `Invoke-ImperionKaseyaImport`, plus
  `Set-ImperionPolicyGoldenState` / `Get-ImperionPolicyDrift`.
- **`Initialize-ImperionContext`** replaces `_bootstrap.ps1`: loads config + secret-name map,
  sets runtime paths, unlocks the SecretStore. Machine config lives in
  **`%ProgramData%\Imperion\`** — outside the module, so module upgrades never clobber it.
- **`build/Install-ImperionModule.ps1`** copies the module to a versioned folder under a
  `PSModulePath` location and seeds config templates.
- **`Initialize-ImperionUnattended`** and **`Register-ImperionTask`** are cmdlets too; tasks
  run `pwsh -Command "Import-Module ImperionPipeline; Initialize-ImperionContext; <cmdlet>"`.

## Consequences

### Security impact

- **Security:** unchanged posture; config/secrets stay out of the module and the repo.

### Operational impact

- **Operational:** clean install/upgrade story; cmdlets are discoverable (`Get-Command
  -Module ImperionPipeline`, comment-based help) and composable in an operator console.

## Future considerations

- **Future:** can publish to an internal PSRepository / sign the module; CI can run
  `Test-ModuleManifest` + Pester + PSScriptAnalyzer.

## Cross-references

This repo `CLAUDE.md §4`; [deployment](../deployment/README.md).
