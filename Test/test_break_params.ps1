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

# ----- Task 4: separator-first break (UsesCommaLast = False, the default) -----
# Format a unit containing one routine declaration; return the full output.
function FmtDecl([string]$decl, [string]$flags) {
  $u = @(
    'unit probe;'
    'interface'
    'type'
    '  TDemo = class'
    "    $decl"
    '  end;'
    'implementation'
    'end.'
  ) -join "`r`n"
  $src = Join-Path $env:TEMP 'bparm_in.pas'
  $out = Join-Path $env:TEMP 'bparm_out.pas'
  Set-Content -Path $src -Value $u -Encoding ascii
  $argv = @($flags -split ' ' | Where-Object { $_ -ne '' })
  & $exe --ini $ini $src @argv --o $out | Out-Null
  $t = Get-Content $out -Raw
  Remove-Item $src,$out -Force -ErrorAction SilentlyContinue
  return $t
}

$on  = FmtDecl 'procedure Go(const A: string; B: Integer; out C: Boolean);' '--break-params'
$off = FmtDecl 'procedure Go(const A: string; B: Integer; out C: Boolean);' '--no-break-params'

# NOTE: output is CRLF, so end-of-line anchors are written '\s*$' (a bare '$'
# cannot match before the '\r'). Same convention as test_break_control.ps1.
MustMatch $on '(?m)procedure Go\(\s*$'      'on: open paren ends the header line'
MustMatch $on '(?m)^\s+const A: string\s*$' 'on: first param bare, no leading separator'
MustMatch $on '(?m)^\s+; B: Integer\s*$'    'on: second param separator-first'
MustMatch $on '(?m)^\s+; out C: Boolean\s*$' 'on: third param separator-first'
MustMatch $on '(?m)^\s+\);\s*$'             'on: close paren on its own line'
MustMatch $off '(?m)procedure Go\(const A: string; B: Integer; out C: Boolean\);' 'off: stays inline (default)'

# A function's return type rides the closing line.
$fn = FmtDecl 'function Calc(A: Integer; B: Integer): Boolean;' '--break-params'
MustMatch $fn '(?m)^\s+\): Boolean;\s*$' 'on: return type rides the close-paren line'

# NON-GOAL: a single-parameter header stays inline (2+ threshold).
$one = FmtDecl 'procedure Log(const AMsg: string);' '--break-params'
MustMatch $one '(?m)procedure Log\(const AMsg: string\);' 'threshold: single param stays inline'

# NON-GOAL: a zero-parameter header is untouched.
$zero = FmtDecl 'procedure Reset;' '--break-params'
MustMatch $zero '(?m)procedure Reset;' 'threshold: no params untouched'

Finish 'break_params'
