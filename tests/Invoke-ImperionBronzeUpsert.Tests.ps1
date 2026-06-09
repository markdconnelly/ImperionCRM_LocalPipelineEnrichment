#Requires -Modules Pester
# Hermetic tests for Invoke-ImperionBronzeUpsert using a fake Npgsql connection that captures
# the generated SQL and scripts the RETURNING reader (no database required).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force

    # ChangedFlags: one bool per row the RETURNING clause yields (true=insert, false=update).
    # Rows not yielded are 'unchanged' (content_hash matched). Capture is a hashtable the test
    # reads CommandText/param count back from.
    function New-FakeConn {
        param([bool[]] $ChangedFlags, [hashtable] $Capture)
        $reader = [pscustomobject]@{ Q = [System.Collections.Queue]::new(@($ChangedFlags)); Cur = $false }
        $reader | Add-Member ScriptMethod Read { if ($this.Q.Count) { $this.Cur = [bool]$this.Q.Dequeue(); $true } else { $false } } -Force
        $reader | Add-Member ScriptMethod GetBoolean { param($i) $this.Cur } -Force
        $reader | Add-Member ScriptMethod Dispose { } -Force

        $params = [pscustomobject]@{ Count = 0 }
        $params | Add-Member ScriptMethod Add { param($p) $this.Count++ } -Force

        $cmd = [pscustomobject]@{ CommandText = $null; Parameters = $params; Reader = $reader; Capture = $Capture }
        $cmd | Add-Member ScriptMethod CreateParameter { [pscustomobject]@{ ParameterName = $null; Value = $null } } -Force
        $cmd | Add-Member ScriptMethod ExecuteReader { $this.Capture.Sql = $this.CommandText; $this.Capture.ParamCount = $this.Parameters.Count; $this.Reader } -Force
        $cmd | Add-Member ScriptMethod Dispose { } -Force

        $conn = [pscustomobject]@{ Cmd = $cmd }
        $conn | Add-Member ScriptMethod CreateCommand { $this.Cmd } -Force
        return $conn
    }

    function New-Rows { 1..3 | ForEach-Object { [pscustomobject]@{ tenant_id = 't'; source = 's'; external_id = "e$_"; name = "n$_"; content_hash = "h$_"; raw_payload = '{}' } } }
}

Describe 'Invoke-ImperionBronzeUpsert' {
    It 'returns a zero tally without touching the DB for empty input' {
        $cap = @{}
        $tally = Invoke-ImperionBronzeUpsert -Connection (New-FakeConn -ChangedFlags @() -Capture $cap) -Table 'foo' -Rows @()
        $tally.scanned | Should -Be 0
        $cap.ContainsKey('Sql') | Should -BeFalse
    }

    It 'counts inserted / updated / unchanged from the RETURNING reader' {
        $cap = @{}
        # 3 rows scanned; reader yields 2 (one insert, one update); the third is unchanged.
        $tally = Invoke-ImperionBronzeUpsert -Connection (New-FakeConn -ChangedFlags @($true, $false) -Capture $cap) -Table 'foo' -Rows (New-Rows)
        $tally.scanned   | Should -Be 3
        $tally.inserted  | Should -Be 1
        $tally.updated   | Should -Be 1
        $tally.unchanged | Should -Be 1
    }

    It 'emits change-detecting upsert SQL (ON CONFLICT + content_hash guard + RETURNING xmax)' {
        $cap = @{}
        Invoke-ImperionBronzeUpsert -Connection (New-FakeConn -ChangedFlags @($true) -Capture $cap) -Table 'm365_devices' -Rows (New-Rows) | Out-Null
        $cap.Sql | Should -Match 'INSERT INTO "m365_devices"'
        $cap.Sql | Should -Match 'ON CONFLICT \("tenant_id", "source", "external_id"\)'
        $cap.Sql | Should -Match 'content_hash IS DISTINCT FROM EXCLUDED\.content_hash'
        $cap.Sql | Should -Match 'RETURNING \(xmax = 0\)'
    }

    It 'casts JSON columns to jsonb and binds one parameter per cell' {
        $cap = @{}
        Invoke-ImperionBronzeUpsert -Connection (New-FakeConn -ChangedFlags @() -Capture $cap) -Table 'foo' -Rows (New-Rows) | Out-Null
        $cap.Sql        | Should -Match '::jsonb'      # raw_payload default JsonColumn
        $cap.ParamCount | Should -Be 18                # 3 rows x 6 columns
    }

    It 'honors custom key columns in the conflict target' {
        $cap = @{}
        $rows = @([pscustomobject]@{ id = '1'; content_hash = 'h'; raw_payload = '{}' })
        Invoke-ImperionBronzeUpsert -Connection (New-FakeConn -ChangedFlags @($true) -Capture $cap) -Table 'foo' -Rows $rows -KeyColumns @('id') | Out-Null
        $cap.Sql | Should -Match 'ON CONFLICT \("id"\)'
    }

    It '-NoChangeDetect omits the content_hash guard (ADR-0039 per-source shape)' {
        $cap = @{}
        # televy/darkwebid shape: external_ref UNIQUE + payload_bronze, no content_hash column.
        $rows = @([pscustomobject]@{ external_ref = 'x1'; payload_bronze = '{}' })
        Invoke-ImperionBronzeUpsert -Connection (New-FakeConn -ChangedFlags @($true) -Capture $cap) -Table 'televy_reports' `
            -Rows $rows -KeyColumns @('external_ref') -JsonColumns @('payload_bronze') -NoChangeDetect | Out-Null
        $cap.Sql | Should -Match 'ON CONFLICT \("external_ref"\)'
        $cap.Sql | Should -Not -Match 'content_hash'
        $cap.Sql | Should -Match '::jsonb'              # payload_bronze placeholder cast to jsonb
        $cap.Sql | Should -Match 'RETURNING \(xmax = 0\)'
    }
}
