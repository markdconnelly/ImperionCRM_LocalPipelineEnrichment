#Requires -Modules Pester
# Hermetic tests for Invoke-ImperionDbQuery using a fake Npgsql command/reader (no database).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force

    # $Rows: array of [ordered] column->value maps the reader will yield (in order). A $null value
    # is reported as DBNull. $Cap captures CommandText + bound parameter names/values.
    function New-FakeQueryConn {
        param([object[]] $Rows, [hashtable] $Cap)
        $reader = [pscustomobject]@{ Rows = @($Rows); Idx = -1 }
        $reader | Add-Member ScriptMethod Read { $this.Idx++; $this.Idx -lt $this.Rows.Count } -Force
        $reader | Add-Member ScriptProperty FieldCount { @($this.Rows[$this.Idx].Keys).Count } -Force
        $reader | Add-Member ScriptMethod GetName { param($i) @($this.Rows[$this.Idx].Keys)[$i] } -Force
        $reader | Add-Member ScriptMethod GetValue { param($i) @($this.Rows[$this.Idx].Values)[$i] } -Force
        $reader | Add-Member ScriptMethod IsDBNull { param($i) $null -eq @($this.Rows[$this.Idx].Values)[$i] } -Force
        $reader | Add-Member ScriptMethod Dispose { } -Force

        $params = [pscustomobject]@{ Bound = @{} }
        $params | Add-Member ScriptMethod Add { param($p) $this.Bound[$p.ParameterName] = $p.Value } -Force

        $cmd = [pscustomobject]@{ CommandText = $null; Parameters = $params; Reader = $reader; Cap = $Cap }
        $cmd | Add-Member ScriptMethod CreateParameter { [pscustomobject]@{ ParameterName = $null; Value = $null } } -Force
        $cmd | Add-Member ScriptMethod ExecuteReader { $this.Cap.Sql = $this.CommandText; $this.Cap.Bound = $this.Parameters.Bound; $this.Reader } -Force
        $cmd | Add-Member ScriptMethod Dispose { } -Force

        $conn = [pscustomobject]@{ Cmd = $cmd }
        $conn | Add-Member ScriptMethod CreateCommand { $this.Cmd } -Force
        return $conn
    }
}

Describe 'Invoke-ImperionDbQuery' {
    It 'maps each reader row to a PSCustomObject with the column values' {
        $cap = @{}
        $rows = @([ordered]@{ external_id = 'e1'; content_hash = 'h1' }, [ordered]@{ external_id = 'e2'; content_hash = 'h2' })
        $result = Invoke-ImperionDbQuery -Connection (New-FakeQueryConn -Rows $rows -Cap $cap) -Sql 'SELECT external_id, content_hash FROM t'
        $result.Count | Should -Be 2
        $result[0].external_id | Should -Be 'e1'
        $result[1].content_hash | Should -Be 'h2'
    }

    It 'converts DBNull columns to $null' {
        $cap = @{}
        $rows = @([ordered]@{ external_id = 'e1'; note = $null })
        $result = Invoke-ImperionDbQuery -Connection (New-FakeQueryConn -Rows $rows -Cap $cap) -Sql 'SELECT external_id, note FROM t'
        $result[0].note | Should -BeNullOrEmpty
        $result[0].external_id | Should -Be 'e1'
    }

    It 'returns an empty result for no rows' {
        $cap = @{}
        @(Invoke-ImperionDbQuery -Connection (New-FakeQueryConn -Rows @() -Cap $cap) -Sql 'SELECT 1').Count | Should -Be 0
    }

    It 'binds named parameters (null -> DBNull)' {
        $cap = @{}
        Invoke-ImperionDbQuery -Connection (New-FakeQueryConn -Rows @() -Cap $cap) -Sql 'SELECT * FROM t WHERE s=@s AND n=@n' -Parameters @{ s = 'm365'; n = $null } | Out-Null
        $cap.Bound['s'] | Should -Be 'm365'
        $cap.Bound['n'] | Should -Be ([DBNull]::Value)
    }
}
