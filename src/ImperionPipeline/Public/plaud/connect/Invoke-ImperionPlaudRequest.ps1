function Invoke-ImperionPlaudRequest {
    <#
    .SYNOPSIS
        Call one Plaud MCP tool (JSON-RPC tools/call) and return its parsed result.
    .DESCRIPTION
        Reusable connect-layer helper (CLAUDE.md §4) for Plaud, which exposes an **MCP
        server, not a REST API** (issue #72 locked design, 2026-06-10:
        https://mcp.plaud.ai/mcp, tools list_files / get_file / get_note /
        get_transcript). Sends a single JSON-RPC 2.0 `tools/call` POST with the per-user
        OAuth bearer token and unwraps the MCP result: `structuredContent` when present,
        else the first text content block (parsed as JSON when possible), else the raw
        result. A JSON-RPC error THROWS — auth expiry must fail loudly so the task layer
        can log-and-skip, never crash the schedule (the OAuth token is browser-granted by
        Mark and refresh can break).

        Pure and StrictMode-safe: the token is passed in (SecretStore secret
        `plaud-oauth-token`), so the function holds no secret and is mockable.

        CONFIRM BEFORE LIVE USE: tool argument names and result shapes are ASSUMPTIONS
        from the Plaud MCP docs — verify on the first authenticated pull.
    .PARAMETER AccessToken
        Plaud OAuth access token (bearer).
    .PARAMETER Tool
        MCP tool name: list_files, get_file, get_note, get_transcript.
    .PARAMETER Arguments
        Tool arguments hashtable (e.g. @{ file_id = '...' }).
    .PARAMETER EndpointUri
        Plaud MCP endpoint. Default https://mcp.plaud.ai/mcp.
    .EXAMPLE
        Invoke-ImperionPlaudRequest -AccessToken $token -Tool list_files
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)][string] $AccessToken,
        [Parameter(Mandatory)][string] $Tool,
        [hashtable] $Arguments = @{},
        [string] $EndpointUri = 'https://mcp.plaud.ai/mcp'
    )

    $request = @{
        jsonrpc = '2.0'
        id      = [guid]::NewGuid().ToString()
        method  = 'tools/call'
        params  = @{ name = $Tool; arguments = $Arguments }
    } | ConvertTo-Json -Depth 10

    $resp = Invoke-ImperionRestWithRetry -Uri $EndpointUri -Method POST -Body $request `
        -Headers @{ Authorization = "Bearer $AccessToken"; Accept = 'application/json' }

    $rpcError = Get-ImperionMember $resp.Body 'error'
    if ($rpcError) {
        throw "Plaud MCP tool '$Tool' failed: $(Get-ImperionMember $rpcError 'message') (code $(Get-ImperionMember $rpcError 'code'))"
    }

    $result = Get-ImperionMember $resp.Body 'result'
    $structured = Get-ImperionMember $result 'structuredContent'
    if ($null -ne $structured) { return $structured }

    $contentBlocks = Get-ImperionMember $result 'content'
    if ($null -ne $contentBlocks) {
        $text = Get-ImperionMember (@($contentBlocks)[0]) 'text'
        if ($text) {
            try { return ($text | ConvertFrom-Json) } catch { return $text }
        }
    }
    return $result
}
