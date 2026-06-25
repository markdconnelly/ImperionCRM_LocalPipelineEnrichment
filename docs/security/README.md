# Security

_ImperionCRM_LocalPipelineEnrichment — `docs/security`_

The certificate trust chain, the read-only-by-default grant model, secret handling, and threat boundaries for an unattended on-prem node.

- [`certificate-trust-chain.md`](certificate-trust-chain.md) — the one machine cert the unattended model hangs off (ADR-0002).
- [`credential-resolution.md`](credential-resolution.md) — how every source/tenant secret resolves from the `connection` registry → Key Vault, holding nothing locally but the node app credential (ADR-0028/0029/0030).
- [`least-privilege-grants.md`](least-privilege-grants.md) — the cert SP's as-built grant set.

> Part of the system-wide `/docs` standard (front-end `CLAUDE.md` §8). See [../../CLAUDE.md](../../CLAUDE.md).

