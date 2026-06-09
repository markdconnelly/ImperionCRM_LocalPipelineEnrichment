# Deployment

How the module + scheduled tasks are installed and updated on the home server.

## Prerequisites
- **PowerShell 7.2+** (`pwsh`).
- Modules: `Microsoft.PowerShell.SecretManagement`, `Microsoft.PowerShell.SecretStore`, `MSAL.PS`, `Pester`, `PSScriptAnalyzer`.
- **Npgsql** .NET assembly — drop `Npgsql.dll` somewhere readable and set `NpgsqlDllPath` in
  config (or `$env:IMPERION_NPGSQL_DLL`). Install via `nuget install Npgsql` or copy from a
  `dotnet add package Npgsql` restore. (Avoids a system-wide ORM dependency.)
- The **certificate** in `Cert:\LocalMachine\My`, the **Entra app** (cert credential,
  read-only grants per ADR-0002), and a **gMSA/service account**.

## Install (ADR-0007)
1. **Install the module:** `.\build\Install-ImperionModule.ps1 -Scope AllUsers` (admin).
   This copies `ImperionPipeline` to a `PSModulePath` folder and seeds config templates into
   `%ProgramData%\Imperion\`.
2. **Edit** `%ProgramData%\Imperion\pipeline.config.psd1` (thumbprint, client id, partner
   tenant, DB host/user, paths) and `secret-names.psd1` (adjust names if desired).
3. **Unattended bootstrap:** `Import-Module ImperionPipeline; Initialize-ImperionUnattended
   -CertThumbprint <thumb> -TaskIdentity 'DOMAIN\svc-imperion$'` (admin) — SecretStore + CMS
   password + cert key ACL.
4. **Add secrets:** `Set-Secret -Vault ImperionStore -Name itglue-read-api-key …`.
5. **Apply the proposed DDL** (`/sql`) via a **front-end migration** (schema ownership,
   ADR-0005). Cmdlets fail loudly until the tables exist.
6. **Register tasks:** `Register-ImperionTask -TaskIdentity 'DOMAIN\svc-imperion$'`.

## Update
Pull the repo, re-run `Install-ImperionModule.ps1` (installs the new version side-by-side),
then `Register-ImperionTask` to refresh definitions. Tasks `Import-Module ImperionPipeline`
each run, picking up the highest installed version.

## Verify
- `Get-Command -Module ImperionPipeline` lists the cmdlets; `Test-ModuleManifest`.
- `Invoke-Pester ./tests` and `Invoke-ScriptAnalyzer -Path ./src,./build -Recurse -Settings ./PSScriptAnalyzerSettings.psd1`.
- Run one cmdlet manually (`Initialize-ImperionContext; Invoke-ImperionServicePrincipalSync`)
  and inspect `logs/imperion-<date>.jsonl` for `Metric` lines.

## CI
A GitHub Actions workflow should gate PRs on lint + Pester + docs checks (mirrors the
siblings' CI). Add under `.github/workflows/` when the repo is pushed.

> Part of the system-wide `/docs` standard (front-end `CLAUDE.md` §8). See [../../CLAUDE.md](../../CLAUDE.md).
