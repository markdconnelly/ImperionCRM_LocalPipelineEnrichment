function Resolve-ImperionInteractionAllowlist {
    <#
    .SYNOPSIS
        Resolve the config-driven two-person interaction allowlist (the principals whose
        client communications are captured), or $null when no config is present.
    .DESCRIPTION
        Module-internal config loader for the scoped interaction collectors (issue #199,
        ADR-0022). The set of Imperion principals whose mail / Teams chat is captured is
        DATA, not code: it lives in a machine config json under `%ProgramData%\Imperion\`
        (default `interaction-allowlist.json`) so the set can change WITHOUT a code release
        (CLAUDE.md §4 machine-config-outside-the-module). v1 is Derek Rankin + Mark
        Connelly, but the collector hardcodes NO names — it reads them here.

        The json shape (see config/interaction-allowlist.example.json):
            {
              "principals": [
                { "upn": "derek@imperionllc.com" },
                { "upn": "mark@imperionllc.com" }
              ]
            }
        Only the `upn` of each principal is used (case-insensitive). Extra keys (display
        name, notes) are ignored — they document the file for a human editor.

        RESOLUTION (mirrors the per-machine config idiom, ADR-0007 Initialize-ImperionContext):
          1. an explicit -Path wins (test / on-demand);
          2. else `$env:IMPERION_INTERACTION_ALLOWLIST` when set;
          3. else `%ProgramData%\Imperion\interaction-allowlist.json`.

        DORMANT / FAIL-CLOSED: when the file is absent or carries no usable principal, this
        returns `$null`. The caller treats $null as "nothing to capture" and exits cleanly
        (CLAUDE.md §3/§8 — never run wide-open; an unconfigured node captures nothing rather
        than everything). The returned UPNs are NOT logged (they are employee identifiers).
    .PARAMETER Path
        Optional explicit path to the allowlist json (wins over env / ProgramData).
    .OUTPUTS
        [string[]] of lower-cased principal UPNs, or $null when unconfigured.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [string] $Path
    )

    if (-not $Path) {
        $Path = if ($env:IMPERION_INTERACTION_ALLOWLIST) {
            $env:IMPERION_INTERACTION_ALLOWLIST
        }
        else {
            Join-Path $env:ProgramData 'Imperion\interaction-allowlist.json'
        }
    }

    if (-not (Test-Path -LiteralPath $Path)) { return $null }

    # A malformed file is an operator error, not a normal dormant case: let ConvertFrom-Json
    # throw so the task-level catch surfaces it (never silently capture nothing because the
    # json was broken).
    $config = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json

    $principalUpns = @(Get-ImperionMember $config 'principals') |
        Where-Object { $_ } |
        ForEach-Object { Get-ImperionMember $_ 'upn' } |
        Where-Object { $_ -and "$_".Trim() } |
        ForEach-Object { "$_".Trim().ToLowerInvariant() } |
        Select-Object -Unique

    if (@($principalUpns).Count -eq 0) { return $null }
    return [string[]]@($principalUpns)
}
