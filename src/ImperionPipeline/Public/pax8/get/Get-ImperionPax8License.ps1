function Get-ImperionPax8License {
    <#
    .SYNOPSIS
        Collect Pax8 license assignments and flatten them to pax8_licenses bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for Pax8 (issue #279, epic #1042) — who/what a
        subscription's seats are assigned to: the PROVISION LINK the merge (#280) ties to a
        silver agreement line / device, and the actual-licensed-seat count the true-up (#1041)
        reconciles. Pure procurement data: flattens STRAIGHT to Postgres and SKIPS the IT Glue
        hub (ADR-0006).

        AUTH: an MSP-WIDE COMPANY credential (OAuth2 client-credentials) resolved by
        Resolve-ImperionPax8Credential; Invoke-ImperionPax8Request owns the bearer exchange +
        page-walk. GATED: the resolver throws until provisioned (Mark-gated) and the scheduled
        task logs the gap + exits cleanly (idempotent re-run converges).

        TARGET: bronze `pax8_licenses` (front-end migration 0161). tenant_id = the Pax8
        partner/account id; per-customer key is `company_id`, per-subscription key is
        `subscription_id`. external_id = the Pax8 license `id` (stable) → idempotent upsert. NEVER
        creates the table; fails loudly if absent (ADR-0005).

        CONFIRM BEFORE LIVE USE: Pax8 may expose license/seat assignments under a usage-summary
        surface rather than a flat `/v1/licenses` collection — the -Path is a single constant to
        correct on the first live pull. Field names are modeled from the documented API; unmatched
        columns land NULL and the full payload survives in raw_payload (the Datto/KQM precedent).
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant (the Pax8 account).
    .PARAMETER BaseUri
        Pax8 API origin. Default 'https://api.pax8.com'.
    .EXAMPLE
        Get-ImperionPax8License | Set-ImperionPax8LicenseToBronze
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId,
        [string] $BaseUri = 'https://api.pax8.com'
    )

    $cfg = Get-ImperionConfig
    if (-not $TenantId) { $TenantId = $cfg.LocalTenantId }
    $cred = Resolve-ImperionPax8Credential

    $licenses = Invoke-ImperionPax8Request @cred -Path '/v1/licenses' -BaseUri $BaseUri

    $firstOf = {
        param($record, [string[]] $candidates)
        foreach ($candidate in $candidates) {
            $value = Get-ImperionPropertyPath -InputObject $record -Path $candidate
            if ($null -ne $value -and "$value" -ne '') { return $value }
        }
    }

    # Column set mirrors front-end migration 0161 (pax8_licenses).
    $map = [ordered]@{
        pax8_license_id = { param($l) & $firstOf $l @('id', 'licenseId') }
        subscription_id = { param($l) & $firstOf $l @('subscriptionId', 'subscription.id') }
        company_id      = { param($l) & $firstOf $l @('companyId', 'company.id') }
        product_id      = { param($l) & $firstOf $l @('productId', 'product.id') }
        assigned_to     = { param($l) & $firstOf $l @('assignedTo', 'assignee', 'assigneeEmail', 'userPrincipalName') }
        quantity        = { param($l) & $firstOf $l @('quantity', 'assignedQuantity', 'seats') }
        status          = { param($l) & $firstOf $l @('status', 'state') }
    }

    $licenses | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'pax8' -TenantId $TenantId -ExternalIdProperty 'id'
}
