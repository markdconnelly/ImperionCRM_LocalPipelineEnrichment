function Test-ImperionScopedInteraction {
    <#
    .SYNOPSIS
        Decide whether a communication is in scope for capture: an allowlisted principal AND a
        client counterpart are both participants (private predicate).
    .DESCRIPTION
        The scope predicate for the scoped interaction collectors (issue #199, ADR-0022). It is
        STRICTER than Test-ImperionCrossOrgComm (which keeps any Imperion↔client domain cross):
        a communication is captured ONLY when BOTH hold over its participant addresses:

          1. an ALLOWLISTED Imperion principal (Derek/Mark — config-driven, never hardcoded) is
             a participant; AND
          2. a CLIENT COUNTERPART is a participant — a participant whose exact address is a known
             silver client-contact email, OR whose domain is a known client domain
             (Resolve-ImperionClientContactSet).

        This drops, by construction:
          * internal-only threads (no client counterpart);
          * threads with a non-client external party (e.g. a vendor) and no client counterpart;
          * any thread that does not involve an allowlisted principal — even Imperion↔client
            mail of an employee NOT on the two-person allowlist.

        Pure function over the participant list + the two resolved sets — fully unit-testable,
        no I/O. Address comparison is case-insensitive; blank/invalid addresses are ignored.
        The principal's own address is NOT eligible as the "client counterpart" (an allowlisted
        principal cannot satisfy both halves alone).
    .PARAMETER Participant
        All participant email addresses on the communication (sender + recipients for mail;
        members / message author for Teams).
    .PARAMETER AllowedPrincipal
        The config-driven allowlist of Imperion principal UPNs (Resolve-ImperionInteractionAllowlist).
    .PARAMETER ClientEmail
        Set of known client-contact emails (Resolve-ImperionClientContactSet .Emails).
    .PARAMETER ClientDomain
        Set of known client domains (Resolve-ImperionClientContactSet .Domains).
    .EXAMPLE
        Test-ImperionScopedInteraction -Participant @('derek@imperionllc.com','sam@acme.com') `
            -AllowedPrincipal @('derek@imperionllc.com') `
            -ClientEmail ([System.Collections.Generic.HashSet[string]]::new()) `
            -ClientDomain ([System.Collections.Generic.HashSet[string]]@('acme.com'))
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [string[]] $Participant,
        [string[]] $AllowedPrincipal = @(),
        [System.Collections.Generic.HashSet[string]] $ClientEmail = ([System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)),
        [System.Collections.Generic.HashSet[string]] $ClientDomain = ([System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase))
    )

    $principalSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($p in @($AllowedPrincipal)) { if ($p -and "$p".Trim()) { [void]$principalSet.Add("$p".Trim()) } }
    if ($principalSet.Count -eq 0) { return $false }

    $addresses = @($Participant) |
        Where-Object { $_ -and ($_ -like '*@*') } |
        ForEach-Object { "$_".Trim().ToLowerInvariant() } |
        Where-Object { $_ }

    $hasPrincipal = $false
    $hasClient = $false
    foreach ($address in $addresses) {
        if ($principalSet.Contains($address)) {
            $hasPrincipal = $true
            # An allowlisted principal is never its own client counterpart.
            continue
        }
        if (-not $hasClient) {
            $domain = (($address -split '@')[-1]).Trim()
            if ($ClientEmail.Contains($address) -or ($domain -and $ClientDomain.Contains($domain))) {
                $hasClient = $true
            }
        }
    }

    return ($hasPrincipal -and $hasClient)
}
