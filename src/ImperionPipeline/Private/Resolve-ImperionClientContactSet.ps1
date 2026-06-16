function Resolve-ImperionClientContactSet {
    <#
    .SYNOPSIS
        Resolve the set of known client/contact email addresses (and their domains) from the
        silver `contact` / `account` entities, for the scoped-interaction counterpart test.
    .DESCRIPTION
        Module-internal silver lookup for the scoped interaction collectors (issue #199,
        ADR-0022). The scope rule (issue #199) keeps a communication ONLY when an allowlisted
        Imperion principal AND one of OUR CLIENTS/CONTACTS are both participants. This resolves
        "our clients/contacts" from the authoritative silver layer rather than a hardcoded /
        domain-guessed list: every `contact.email` that belongs to a real account is a known
        counterpart, and the email's DOMAIN is the per-account client domain.

        Returns a result object with two case-insensitive lookup sets:
          * `Emails`  — the exact client-contact addresses (a HashSet[string], lower-cased);
          * `Domains` — the distinct domains of those addresses (a HashSet[string]).
        A counterpart participant matches when its address is in `Emails` OR its domain is in
        `Domains` (the predicate Test-ImperionScopedInteraction applies). Domain matching keeps
        a thread with a known client whose individual sender is not yet a silver contact row;
        exact-email matching is the tightest case.

        Pure silver read — never writes. Reads `contact` joined to `account` so only contacts
        that resolve to a real account (a client/prospect, not an orphan import) are kept. The
        returned addresses are PII (client contact emails): they stay in memory for the filter
        and are NEVER logged (CLAUDE.md §8 — counts only).

        EMPTY / DORMANT: with no client contacts (empty silver, or pre-seed), both sets are
        empty and the predicate keeps nothing — the collector lands zero rows cleanly.
    .PARAMETER Connection
        An open Npgsql connection (the collector opens/disposes one when omitted). Read-only.
    .OUTPUTS
        [pscustomobject] @{ Emails = [HashSet[string]]; Domains = [HashSet[string]] }
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)] $Connection
    )

    $emails = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $domains = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    # Only contacts that resolve to a real account are client counterparts. INNER JOIN drops
    # orphan contacts (no owning account) so a stray import can never widen the capture scope.
    $clientContacts = @(Invoke-ImperionDbQuery -Connection $Connection -Sql @'
SELECT c.email
  FROM contact c
  JOIN account a ON a.id = c.account_id
 WHERE c.email IS NOT NULL AND c.email <> ''
'@)

    foreach ($contactRow in $clientContacts) {
        $email = "$(Get-ImperionMember $contactRow 'email')".Trim().ToLowerInvariant()
        if (-not $email -or $email -notlike '*@*') { continue }
        [void]$emails.Add($email)
        $domain = (($email -split '@')[-1]).Trim()
        if ($domain) { [void]$domains.Add($domain) }
    }

    [pscustomobject]@{ Emails = $emails; Domains = $domains }
}
