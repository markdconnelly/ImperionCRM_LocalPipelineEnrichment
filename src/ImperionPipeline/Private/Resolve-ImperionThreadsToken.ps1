function Resolve-ImperionThreadsToken {
    <#
    .SYNOPSIS
        Resolve the long-lived Threads access token from the company credential registry.
    .DESCRIPTION
        Thin vendor adapter (LocalPipeline #356, front-end ADR-0125 / epic #1334) over
        Resolve-ImperionCompanyCredential -Provider 'threads' (the DB-authoritative
        `connection` registry → Key Vault path, ADR-0103 / #319; the UniFi precedent).

        Threads is a NET-NEW connector `conn-company-threads` (company scope) with its OWN
        Threads OAuth long-lived token — it shares no token or code with the FB/IG Meta
        integration (`conn-company-meta`, 0075). The token is resolved by reference from Key
        Vault via the cert-backed app SP, returned to the immediate caller, and NEVER logged;
        the connect layer carries it as an `Authorization: Bearer` header (never the
        querystring) and strips any access_token parameter from paging URLs as the second guard.

        Dormant-safe: when the company `threads` connection row is absent or its Key Vault
        secret resolves empty (token not entered / App Review not yet cleared) this returns
        $null, so a caller can log + no-op rather than crash the schedule. Pass -FailClosed to
        throw instead. An explicit -Token short-circuits resolution (test / manual-run path).
    .PARAMETER Token
        Explicit Threads token override; bypasses registry resolution when supplied.
    .PARAMETER Connection
        Optional open Npgsql connection to reuse for the registry lookup.
    .PARAMETER FailClosed
        Throw instead of returning $null when no usable credential is found.
    .EXAMPLE
        $token = Resolve-ImperionThreadsToken
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string] $Token,
        $Connection,
        [switch] $FailClosed
    )

    if ($Token) { return $Token }
    return Resolve-ImperionCompanyCredential -Provider 'threads' -Field 'accessToken' `
        -Connection $Connection -FailClosed:$FailClosed
}
