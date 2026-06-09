function Write-ImperionLog {
    <#
    .SYNOPSIS
        Emit a structured JSON log line (and a human-readable console line) for a pipeline run.
    .DESCRIPTION
        Every pipeline task logs structured events: run id, source, level, message, and any
        metrics (scanned/created/updated/unchanged/errors/duration/cost). JSON lines are
        appended to a per-run file under the configured log directory so runs are auditable
        ("nothing changed, moved on" is visible). Never log secrets.
    .PARAMETER Message
        Human-readable message.
    .PARAMETER Level
        Info | Warn | Error | Metric.
    .PARAMETER Source
        Logical source key (e.g. 'm365', 'azure', 'itglue').
    .PARAMETER Data
        Optional hashtable of structured fields merged into the JSON record.
    .PARAMETER RunId
        Correlation id for the run; defaults to the module-scoped run id.
    .EXAMPLE
        Write-ImperionLog -Level Metric -Source m365 -Message 'sync complete' -Data @{ scanned=120; unchanged=118; updated=2 }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Message,
        [ValidateSet('Info', 'Warn', 'Error', 'Metric')][string] $Level = 'Info',
        [string] $Source = 'pipeline',
        [hashtable] $Data,
        [string] $RunId = $script:ImperionRunId
    )

    if (-not $RunId) { $RunId = [guid]::NewGuid().ToString(); $script:ImperionRunId = $RunId }
    $logDir =
        if ($script:ImperionLogDirectory) { $script:ImperionLogDirectory }
        elseif ($env:IMPERION_LOG_DIR) { $env:IMPERION_LOG_DIR }
        else { Join-Path (Get-Location) 'logs' }
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }

    $record = [ordered]@{
        ts      = (Get-Date).ToString('o')
        runId   = $RunId
        level   = $Level
        source  = $Source
        message = $Message
    }
    if ($Data) { foreach ($k in $Data.Keys) { $record[$k] = $Data[$k] } }

    $json = ($record | ConvertTo-Json -Compress -Depth 6)
    $file = Join-Path $logDir ("imperion-{0}.jsonl" -f (Get-Date -Format 'yyyyMMdd'))
    Add-Content -Path $file -Value $json -Encoding utf8

    $color = switch ($Level) { 'Error' { 'Red' } 'Warn' { 'Yellow' } 'Metric' { 'Cyan' } default { 'Gray' } }
    Write-Host ("[{0}] {1,-6} {2,-8} {3}" -f $record.ts, $Level, $Source, $Message) -ForegroundColor $color
}
