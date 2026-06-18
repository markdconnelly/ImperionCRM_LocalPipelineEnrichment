#Requires -Version 7.2
<#
.SYNOPSIS
    Drift guard for the vendored vector contract (local-pipeline #231 / front-end ADR-0102).
.DESCRIPTION
    The front end owns the ONE machine-readable home for the pinned vector contract
    (ImperionCRM/db/contracts/vector-contract.json). This module vendors a byte-identical
    copy at src/ImperionPipeline/Private/vector-contract.json so the unattended runtime has
    no cross-repo dependency. This script — run in CI — fetches the canonical file and fails
    if the vendored copy has drifted, so a contract bump in the front end turns this repo's
    CI red until it re-vendors. That enforcement is what makes "one home" real across repos.

    Both repos are public, so the fetch needs no credentials.
.EXAMPLE
    pwsh ./build/Test-VectorContractSync.ps1
#>
[CmdletBinding()]
param(
    [string] $CanonicalUri = 'https://raw.githubusercontent.com/markdconnelly/ImperionCRM/main/db/contracts/vector-contract.json'
)

$ErrorActionPreference = 'Stop'

$vendoredPath = Join-Path $PSScriptRoot '..' 'src' 'ImperionPipeline' 'Private' 'vector-contract.json'
if (-not (Test-Path -LiteralPath $vendoredPath)) {
    throw "Vendored vector contract not found at '$vendoredPath'."
}

# Compare by value, not formatting/line-endings — round-trip both through ConvertFrom/To-Json.
$vendored = Get-Content -LiteralPath $vendoredPath -Raw | ConvertFrom-Json | ConvertTo-Json -Depth 20

$response = Invoke-WebRequest -Uri $CanonicalUri -UseBasicParsing
$canonical = $response.Content | ConvertFrom-Json | ConvertTo-Json -Depth 20

if ($vendored -ne $canonical) {
    Write-Error (
        "Vendored vector contract has DRIFTED from the front-end canonical.`n" +
        "  canonical: $CanonicalUri`n" +
        "  vendored : $vendoredPath`n" +
        'Re-vendor (copy the canonical over the vendored copy) — see Get-ImperionVectorContract.ps1.'
    )
    exit 1
}

Write-Host 'Vector contract in sync with the front-end canonical.'
