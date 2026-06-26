# Client tenant onboarding — read-only "Imperion Client Onboarding" app

How to grant the Imperion pipeline read-only access to a **client's** Microsoft 365 /
Azure estate, under the **per-client app** model (backend ADR-0076, registry ADR-0103, LP
ADR-0028). Each client tenant gets its **own** app registration; its credential is
custodied in Imperion Key Vault and resolved per tenant by the pipeline
(`Resolve-ImperionTenantCredential`, LP #257).

> **This is a security event** (CLAUDE.md §3/§8). One app + consent per client, read-only,
> severable by deleting the registry row / KV secret.

## 1. Create the app in the client tenant (Global Admin, once per tenant)

Run [`build/New-ImperionClientOnboardingApp.ps1`](../../build/New-ImperionClientOnboardingApp.ps1)
signed in as a **Global Administrator of the client tenant**:

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser   # first time only
.\build\New-ImperionClientOnboardingApp.ps1 -TenantId <client-tenant-id-or-domain>
```

The script (idempotent, `-WhatIf` supported):
1. Connects to Graph as the tenant's Global Admin.
2. Resolves each permission **by name** to its app-role id from that tenant's Graph service
   principal — no hard-coded GUIDs.
3. Creates (or reuses) the **Imperion Client Onboarding** app + service principal.
4. Sets the read-only `requiredResourceAccess` and **grants admin consent**.
5. Creates a client secret and prints it **once**.

It prints `Tenant Id`, `Client Id`, `Auth method`, the **secret** (once), and the granted
permission list.

### Permissions granted (read-only estate/posture)
`User.Read.All` · `Group.Read.All` · `GroupMember.Read.All` · `Directory.Read.All` ·
`Device.Read.All` · `DeviceManagementManagedDevices.Read.All` · `DeviceManagementApps.Read.All` ·
`DeviceManagementConfiguration.Read.All` · `DeviceManagementServiceConfig.Read.All` ·
`SecurityEvents.Read.All` · `Policy.Read.All` · `Application.Read.All` ·
`RoleManagement.Read.Directory` · `UserAuthenticationMethod.Read.All` ·
`CustomSecAttributeAssignment.Read.All` · `CustomSecAttributeDefinition.Read.All` ·
`Sites.Read.All` · `InformationProtectionPolicy.Read.All`.

**Gated (off by default):** `-IncludeComms` adds the protected message-body roles
(`Mail.Read`, `Chat.Read.All`, `ChannelMessage.Read.All`, `OnlineMeetings.Read.All`,
`CallRecords.Read.All`) for the scoped-interaction collector (LP ADR-0022, dormant). These
need extra Microsoft approval — only enable when turning that capability on for a client.

**Cert instead of secret:** `-UseCertificate -CertificatePath <.cer>` uploads a public key
instead of minting a secret (preferred long-term; a secret is simpler to seed).

## 2. Seed the credential into Imperion (GUI)

In **Settings → Credentials**, add a client M365 credential (the *Register a client M365
tenant* form, ImperionCRM #950): pick the owning client account, paste the tenant id + the
`App (client) id`, choose **Secret** or **Certificate**, and supply the secret value or the
cert thumbprint. The GUI proxies it to the backend, which custodies the secret in **Key
Vault** (never the database) and writes the `connection` row (scope=client, `provider='m365'`,
`account_id`, `client_id`=the app id (migration 0147; backend #226), `auth_method`,
`keyvault_secret_ref` | `cert_thumbprint`). Then map the tenant → account in **Settings →
Tenant mapping** (`account_tenant`).

## 3. The pipeline picks it up

On its next scheduled run the estate collectors fan out over the **consented-tenant registry**
(`Get-ImperionConsentedTenant`: `account_tenant ⨝` an active `m365` `connection`; #358,
ADR-0030 Decision #4) — **GUI-save is the enable**, no host env edit (CLAUDE.md §1
pull/registry-driven). For each tenant, `Resolve-ImperionTenantCredential -Provider m365`
(issue #257) reads the registry row and returns a credential splat — `@{ ClientId; CertThumbprint }`
or `@{ ClientId; ClientSecret }` — that the token primitives mint a per-client token from,
reading that tenant read-only and failing closed (`-FailClosed`) when the credential is
absent/expired. **Imperion's own tenant is onboarded the same way** (client-zero, ADR-0028).

> Setting `IMPERION_M365_TENANT_IDS` (comma-separated tenant ids) on the host **pins/overrides**
> the registry to that subset — useful for a targeted run, but leave it **unset** for full
> registry-driven discovery. An empty registry **and** unset env → the partner tenant only
> (dormant-safe). The literal tenant-outer single-driver + per-tenant token reuse is a separate
> follow-up (epic #324 slice 3b).

> UniFi consoles are **not** Entra apps — seed those as `provider=unifi` API-key
> credentials in the same GUI; no app-registration script is involved.
