function ConvertTo-ImperionDnsRecordValue {
    <#
    .SYNOPSIS
        Flatten an Azure DNS recordset's typed properties into one stable text value.
    .DESCRIPTION
        Private helper for Get-ImperionDnsZoneObject (front-end ADR-0063). Azure returns a
        recordset's data under a per-type property (aRecords, txtRecords, cnameRecord, ...);
        this collapses the relevant one to a single delimited string so the bronze `value`
        column and its content_hash are stable and human-readable. StrictMode-safe via
        Get-ImperionMember (absent properties yield $null, never throw). Unknown types fall
        back to compact JSON of the properties so nothing is silently dropped.
    .PARAMETER RecordType
        The short record type (A, AAAA, CNAME, MX, NS, TXT, CAA, SRV, SOA, PTR, ...).
    .PARAMETER Properties
        The recordset's `properties` object from ARM.
    .OUTPUTS
        [string] — the delimited record value.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string] $RecordType,
        $Properties
    )

    $p = $Properties
    switch ($RecordType.ToUpperInvariant()) {
        'A'     { return (@(Get-ImperionMember $p 'ARecords')    | ForEach-Object { Get-ImperionMember $_ 'ipv4Address' }) -join '; ' }
        'AAAA'  { return (@(Get-ImperionMember $p 'AAAARecords') | ForEach-Object { Get-ImperionMember $_ 'ipv6Address' }) -join '; ' }
        'CNAME' { return [string](Get-ImperionMember (Get-ImperionMember $p 'CNAMERecord') 'cname') }
        'MX'    { return (@(Get-ImperionMember $p 'MXRecords')   | ForEach-Object { '{0} {1}' -f (Get-ImperionMember $_ 'preference'), (Get-ImperionMember $_ 'exchange') }) -join '; ' }
        'NS'    { return (@(Get-ImperionMember $p 'NSRecords')   | ForEach-Object { Get-ImperionMember $_ 'nsdname' }) -join '; ' }
        'TXT'   { return (@(Get-ImperionMember $p 'TXTRecords')  | ForEach-Object { (@(Get-ImperionMember $_ 'value')) -join '' }) -join '; ' }
        'CAA'   { return (@(Get-ImperionMember $p 'CAARecords')  | ForEach-Object { '{0} {1} {2}' -f (Get-ImperionMember $_ 'flags'), (Get-ImperionMember $_ 'tag'), (Get-ImperionMember $_ 'value') }) -join '; ' }
        'SRV'   { return (@(Get-ImperionMember $p 'SRVRecords')  | ForEach-Object { '{0} {1} {2} {3}' -f (Get-ImperionMember $_ 'priority'), (Get-ImperionMember $_ 'weight'), (Get-ImperionMember $_ 'port'), (Get-ImperionMember $_ 'target') }) -join '; ' }
        'PTR'   { return (@(Get-ImperionMember $p 'PTRRecords')  | ForEach-Object { Get-ImperionMember $_ 'ptrdname' }) -join '; ' }
        'SOA'   { return [string](Get-ImperionMember (Get-ImperionMember $p 'SOARecord') 'host') }
        default {
            if ($null -eq $p) { return '' }
            return ($p | ConvertTo-Json -Compress -Depth 6)
        }
    }
}
