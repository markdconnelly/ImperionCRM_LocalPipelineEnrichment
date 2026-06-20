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

In **Settings → Credentials**, add a client M365 credential: paste the `Client Id` +
`Secret` (or cert thumbprint), pick the owning client account. The GUI custodies the secret
in **Key Vault** (never the database) and writes the `connection` row (scope=client,
`provider=graph`, `account_id`, `external_account_id`=tenant, `auth_method`,
`keyvault_secret_ref`). Then map the tenant → account in **Settings → Tenant mapping**
(`account_tenant`).

## 3. The pipeline picks it up

On its next scheduled run the estate collectors fan out over `account_tenant`, and
`Resolve-ImperionTenantCredential -Provider graph` mints a per-client token from the
registry credential — reading that tenant read-only, fail-closed if the credential is
absent/expired. **Imperion's own tenant is onboarded the same way** (client-zero, ADR-0028).

> UniFi consoles are **not** Entra apps — seed those as `provider=unifi` API-key
> credentials in the same GUI; no app-registration script is involved.
