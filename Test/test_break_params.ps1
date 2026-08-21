# Fixture-based tests for BreakParamsOnePerLine (--break-params, default OFF).
# A routine declaration with 2+ parameters gets one parameter per line;
# separator placement mirrors UsesCommaLast. Exit 0 = pass, 1 = fail.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
$ini = Get-RepoIni   # pin config: personal %APPDATA% profile must not affect tests
Assert-ToolOrSkip 'break_params' $exe

# ----- Task 1: the flag is wired onto every surface -----
$help = & $exe --help 2>&1 | Out-String
MustMatch $help '--break-params'     'help lists --break-params'
MustMatch $help '--no-break-params'  'help lists --no-break-params'

# Generated default INI carries the key (table-driven template).
$tmpIni = Join-Path $env:TEMP 'bparm.ini'
Remove-Item $tmpIni -Force -ErrorAction SilentlyContinue
& $exe --ini $tmpIni --help | Out-Null   # --ini creates the template if absent
if (-not (Test-Path $tmpIni)) { & $exe --ini $tmpIni --stdout 2>&1 | Out-Null }
$iniTxt = if (Test-Path $tmpIni) { Get-Content $tmpIni -Raw } else { '' }
MustMatch $iniTxt 'BreakParamsOnePerLine' 'ini template has BreakParamsOnePerLine'
Remove-Item $tmpIni -Force -ErrorAction SilentlyContinue

# A --break-params run is ACCEPTED (no "unknown option") even before the pass
# exists; behavior assertions arrive in later tasks.
$probe = Join-Path $env:TEMP 'bparm_probe.pas'
@'
unit p; interface implementation
procedure Go(const A: string; B: Integer); begin end;
end.
'@ | Set-Content $probe -Encoding ascii
$err = & $exe --ini $ini $probe --break-params --stdout 2>&1 | Out-String
MustNotMatch $err 'unknown option'  '--break-params accepted'
Remove-Item $probe -Force -ErrorAction SilentlyContinue

Finish 'break_params'
