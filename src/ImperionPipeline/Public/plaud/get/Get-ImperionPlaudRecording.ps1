function Get-ImperionPlaudRecording {
    <#
    .SYNOPSIS
        Collect Plaud recordings (AI note + transcript) and flatten them to bronze rows.
    .DESCRIPTION
        Get-layer collector (CLAUDE.md §6) for issue #72's locked design (2026-06-10):
        Plaud exposes an MCP server (no REST alternative), so this calls `list_files`
        then, per file, `get_note` (AI summary + action items) and `get_transcript`
        (timestamps + speakers) through Invoke-ImperionPlaudRequest, composing ONE flat
        row per recording. Target: the PROPOSED `plaud_recordings` bronze (front-end
        migration pending — schema handoff, docs/integrations/plaud.md) → silver
        `meeting` (migration 0028: plaud_summary / transcript_ref, 1:1 with
        interaction(kind=meeting)) via the follow-up merge.

        AUTH: the per-user OAuth token Mark grants once in a browser, stored in the
        SecretStore (`plaud-oauth-token` — raw token or a JSON blob with access_token).
        Refresh can break and need a human re-login, so an auth failure here THROWS and
        the task layer logs-and-skips — never crashes the schedule (the issue's
        fail-loudly rule).

        CONFIRM BEFORE LIVE USE: tool argument/field names (file id/title/timestamps,
        note/transcript shapes) are ASSUMPTIONS from the Plaud MCP docs.
        Returns rows; does not write. Requires Initialize-ImperionContext.
    .PARAMETER TenantId
        Owning tenant stamped on each row; defaults to the partner tenant.
    .PARAMETER SkipTranscript
        Skip the per-file get_transcript call (summary-only pull; transcripts are the
        bulkiest part).
    .EXAMPLE
        Get-ImperionPlaudRecording | Set-ImperionPlaudRecordingToBronze
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $TenantId,
        [switch] $SkipTranscript
    )

    $cfg = Get-ImperionConfig
    $names = Get-ImperionSecretNames
    if (-not $TenantId) { $TenantId = $cfg.PartnerTenantId }

    # The stored secret may be the raw access token or a JSON blob holding one.
    $storedToken = Get-ImperionSecretValue -Name $names.PlaudOAuthToken
    $accessToken = $storedToken
    if ($storedToken -match '^\s*\{') {
        $tokenBlob = $storedToken | ConvertFrom-Json
        $accessToken = Get-ImperionMember $tokenBlob 'access_token'
        if (-not $accessToken) { throw 'plaud-oauth-token JSON blob has no access_token field.' }
    }

    $listResult = Invoke-ImperionPlaudRequest -AccessToken $accessToken -Tool 'list_files'
    $files = Get-ImperionMember $listResult 'files'
    if ($null -eq $files) { $files = $listResult }   # flat-array shape fallback
    $files = @($files | Where-Object { $_ })
    if ($files.Count -eq 0) {
        Write-ImperionLog -Source 'plaud' -Message 'plaud: no recordings returned by list_files.'
        return @()
    }

    $map = [ordered]@{
        title            = 'title'
        started_at       = 'startedAt'
        duration_seconds = 'duration'
        summary          = { param($recording) Get-ImperionPropertyPath -InputObject $recording -Path 'note.summary' }
        action_items     = { param($recording) (Get-ImperionPropertyPath -InputObject $recording -Path 'note.actionItems') | Join-ImperionValues }
        transcript       = { param($recording) Get-ImperionMember $recording 'transcriptText' }
    }

    $rows = foreach ($file in $files) {
        $fileId = Get-ImperionMember $file 'id'
        if (-not $fileId) { continue }

        $note = Invoke-ImperionPlaudRequest -AccessToken $accessToken -Tool 'get_note' -Arguments @{ file_id = $fileId }
        $file | Add-Member -NotePropertyName 'note' -NotePropertyValue $note -Force

        if (-not $SkipTranscript) {
            $transcript = Invoke-ImperionPlaudRequest -AccessToken $accessToken -Tool 'get_transcript' -Arguments @{ file_id = $fileId }
            # Keep the full transcript object in raw_payload; flatten a text form for the column.
            $transcriptText = if ($transcript -is [string]) { $transcript } else { Get-ImperionMember $transcript 'text' }
            $file | Add-Member -NotePropertyName 'transcript' -NotePropertyValue $transcript -Force
            $file | Add-Member -NotePropertyName 'transcriptText' -NotePropertyValue $transcriptText -Force
        }

        $file | ConvertTo-ImperionFlatObject -PropertyMap $map -Source 'plaud' -TenantId $TenantId -ExternalIdProperty 'id'
    }

    Write-ImperionLog -Source 'plaud' -Message 'plaud recordings collected.' -Data @{ recordings = @($rows).Count }
    return @($rows)
}
