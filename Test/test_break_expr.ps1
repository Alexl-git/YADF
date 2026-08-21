# Fixture-based tests for BreakLongExpressions (--break-expr, default OFF).
# An over-long line is broken at every depth-0 operator, one component per
# line, operator leading; trailing then/do move to their own line at the
# header keyword's column. Exit 0 = pass, 1 = fail.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
$ini = Get-RepoIni   # pin config: personal %APPDATA% profile must not affect tests
Assert-ToolOrSkip 'break_expr' $exe

# ----- Task 1: the flag is wired onto every surface -----
$help = & $exe --help 2>&1 | Out-String
MustMatch $help '--break-expr'     'help lists --break-expr'
MustMatch $help '--no-break-expr'  'help lists --no-break-expr'

$tmpIni = Join-Path $env:TEMP 'bexpr.ini'
Remove-Item $tmpIni -Force -ErrorAction SilentlyContinue
& $exe --ini $tmpIni --stdout 2>&1 | Out-Null
$iniTxt = if (Test-Path $tmpIni) { Get-Content $tmpIni -Raw } else { '' }
MustMatch $iniTxt 'BreakLongExpressions' 'ini template has BreakLongExpressions'
Remove-Item $tmpIni -Force -ErrorAction SilentlyContinue

$probe = Join-Path $env:TEMP 'bexpr_probe.pas'
@'
unit p; interface implementation
procedure Go; var A, B: Boolean; begin if A and B then Writeln(1); end;
end.
'@ | Set-Content $probe -Encoding ascii
$err = & $exe --ini $ini $probe --break-expr --stdout 2>&1 | Out-String
MustNotMatch $err 'unknown option'  '--break-expr accepted'
Remove-Item $probe -Force -ErrorAction SilentlyContinue

Finish 'break_expr'
