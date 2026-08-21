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
function FmtDecl([string]$decl, [string]$flags, [string]$iniPath) {
  if (-not $iniPath) { $iniPath = $ini }
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
  & $exe --ini $iniPath $src @argv --o $out | Out-Null
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

# ----- Task 5: separator-last mirrors UsesCommaLast -----
# UsesCommaLast has NO CLI flag (it is INI/UI only), so pin it through a copy of
# the repo INI. Left in place on purpose: later sections reuse $iniLast.
$iniLast = Join-Path $env:TEMP 'bparm_commalast.ini'
((Get-Content $ini -Raw) -replace '(?m)^UsesCommaLast=.*$', 'UsesCommaLast=true') |
  Set-Content $iniLast -Encoding ascii -NoNewline

$last = FmtDecl 'procedure Go(const A: string; B: Integer);' '--break-params' $iniLast
MustMatch $last '(?m)^\s+const A: string;\s*$' 'comma-last: separator trails the first param'
MustMatch $last '(?m)^\s+B: Integer\);\s*$'    'comma-last: close paren rides the last param'

# ----- Task 5: grouped names split, modifier repeated -----
$grp = FmtDecl 'procedure Copy2(const ASrc, ADest: string; AFlags: Integer);' '--break-params'
MustMatch $grp '(?m)^\s+const ASrc: string\s*$'    'group: first name keeps const'
MustMatch $grp '(?m)^\s+; const ADest: string\s*$' 'group: second name repeats const'
MustMatch $grp '(?m)^\s+; AFlags: Integer\s*$'     'group: ungrouped param unaffected'

# var/out modifiers repeat too, and 2-name groups now cross the 2+ threshold.
$sw = FmtDecl 'procedure Swap(var A, B: Integer);' '--break-params'
MustMatch $sw '(?m)^\s+var A: Integer\s*$'   'group: var repeated (first)'
MustMatch $sw '(?m)^\s+; var B: Integer\s*$' 'group: var repeated (second)'

# Untyped group: no colon, splits on names alone.
$untyped = FmtDecl 'procedure Raw(var A, B);' '--break-params'
MustMatch $untyped '(?m)^\s+var A\s*$'   'untyped: first name'
MustMatch $untyped '(?m)^\s+; var B\s*$' 'untyped: second name'

# Generic type containing a comma must NOT be split on that comma.
$gen = FmtDecl 'procedure Feed(const AMap: TDictionary<string, Integer>; ACount: Integer);' '--break-params'
MustMatch    $gen '(?m)^\s+const AMap: TDictionary<string, Integer>\s*$' 'generic: type comma untouched'
MustNotMatch $gen '(?m)^\s+; Integer>'  'generic: no split inside the type argument list'

# ----- Task 5: the no-split fallbacks -----
# Fallback: '=' default value. Splitting would duplicate the default and, if it
# held a string literal, trip YADF.Guard's exact-sequence check on the whole file.
$def = FmtDecl 'procedure Def(A, B: string = ''x''; C: Integer);' '--break-params'
MustMatch $def '(?m)^\s+A, B: string = ''x''\s*$' 'fallback: defaulted group kept whole'

# Fallback: attribute in the name region.
$attr = FmtDecl 'procedure Att([Ref] const A, B: TRec; C: Integer);' '--break-params'
MustMatch $attr '(?m)^\s+\[Ref\] const A, B: TRec\s*$' 'fallback: attributed group kept whole'

# Fallback: interior comment between names.
$cmt = FmtDecl 'procedure Cmt(const A, {why} B: string; C: Integer);' '--break-params'
MustMatch $cmt '(?m)const A, \{why\} B: string' 'fallback: commented group kept whole'

# NON-GOAL: call-site argument lists are never broken.
$call = FmtDecl 'procedure Uses1(A: Integer; B: Integer);' '--break-params'
MustNotMatch $call '(?m)^\s+; Writeln' 'non-goal: call sites untouched'

Finish 'break_params'
