#Requires -Modules Pester
# Hermetic tests for Invoke-ImperionDbNonQuery using a fake Npgsql command (no database).

BeforeAll {
    $module = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\ImperionPipeline\ImperionPipeline.psd1'
    Import-Module $module -Force

    function New-FakeNonQueryConn {
        param([int] $Affected, [hashtable] $Cap)
        $params = [pscustomobject]@{ Bound = @{} }
        $params | Add-Member ScriptMethod Add { param($p) $this.Bound[$p.ParameterName] = $p.Value } -Force

        $cmd = [pscustomobject]@{ CommandText = $null; Parameters = $params; Affected = $Affected; Cap = $Cap }
        $cmd | Add-Member ScriptMethod CreateParameter { [pscustomobject]@{ ParameterName = $null; Value = $null } } -Force
        $cmd | Add-Member ScriptMethod ExecuteNonQuery { $this.Cap.Sql = $this.CommandText; $this.Cap.Bound = $this.Parameters.Bound; $this.Affected } -Force
        $cmd | Add-Member ScriptMethod Dispose { } -Force

        $conn = [pscustomobject]@{ Cmd = $cmd }
        $conn | Add-Member ScriptMethod CreateCommand { $this.Cmd } -Force
        return $conn
    }
}

Describe 'Invoke-ImperionDbNonQuery' {
    It 'returns the affected row count from ExecuteNonQuery' {
        $cap = @{}
        $n = Invoke-ImperionDbNonQuery -Connection (New-FakeNonQueryConn -Affected 4 -Cap $cap) -Sql 'DELETE FROM t WHERE id=@id' -Parameters @{ id = '1' }
        $n | Should -Be 4
        $cap.Sql | Should -Be 'DELETE FROM t WHERE id=@id'
    }

    It 'binds named parameters (null -> DBNull)' {
        $cap = @{}
        Invoke-ImperionDbNonQuery -Connection (New-FakeNonQueryConn -Affected 1 -Cap $cap) -Sql 'UPDATE t SET note=@n WHERE id=@id' -Parameters @{ n = $null; id = 'x' } | Out-Null
        $cap.Bound['id'] | Should -Be 'x'
        $cap.Bound['n'] | Should -Be ([DBNull]::Value)
    }

    It 'works with no parameters' {
        $cap = @{}
        Invoke-ImperionDbNonQuery -Connection (New-FakeNonQueryConn -Affected 0 -Cap $cap) -Sql 'VACUUM' | Should -Be 0
    }
}
