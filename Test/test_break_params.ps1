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
& $exe --ini $tmpIni --help | Out-Null   # --ini <new path> materialises the template
# This used to fall back to a --stdout run: the help branch ran before
# ExtractIniPath, so --help never saw --ini and never created the file. Fixed
# in YadfMain.RunYadf -- assert it directly instead of papering over it.
if (-not (Test-Path $tmpIni)) { Fail '--ini <new path> --help did not create the template' }
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

# ----- Task 6: idempotency + content-preserving round-trip -----
$idemSrc = Join-Path $env:TEMP 'bparm_idem.pas'
@'
unit probe;
interface
type
  TDemo = class
    procedure Go(const A: string; B: Integer; out C: Boolean);
    function Calc(const ASrc, ADest: string; AFlags: Integer): Boolean;
    procedure Swap(var A, B: Integer);
    procedure Def(A, B: string = 'x'; C: Integer);
    procedure Log(const AMsg: string);
  end;
implementation
procedure TDemo.Go(const A: string; B: Integer; out C: Boolean);
begin
end;
function TDemo.Calc(const ASrc, ADest: string; AFlags: Integer): Boolean;
begin
  Result := True;
end;
procedure TDemo.Swap(var A, B: Integer);
begin
end;
procedure TDemo.Def(A, B: string = 'x'; C: Integer);
begin
end;
procedure TDemo.Log(const AMsg: string);
begin
end;
end.
'@ | Set-Content $idemSrc -Encoding ascii

# NOTE: UsesCommaLast has NO CLI flag -- it is INI-only (YadfMain.pas exposes
# --uses-break for UsesAlwaysBreak, but nothing for UsesCommaLast, and the exe
# rejects an unknown --flag outright). Separator-last is therefore pinned
# through the derived INI $iniLast created in the Task 5 section above.
foreach ($cfg in @(
    @{ Ini = $ini;     Label = 'separator-first' },
    @{ Ini = $iniLast; Label = 'separator-last'  })) {
  $o1 = Join-Path $env:TEMP 'bparm_i1.pas'; $o2 = Join-Path $env:TEMP 'bparm_i2.pas'
  & $exe --ini $cfg.Ini $idemSrc --break-params --o $o1 | Out-Null
  & $exe --ini $cfg.Ini $o1      --break-params --o $o2 | Out-Null
  if ((Get-FileHash $o1).Hash -ne (Get-FileHash $o2).Hash) { Fail ("idempotent: " + $cfg.Label) }
  $chk = & $exe --ini $cfg.Ini --check $o1 2>&1
  if ("$chk" -notmatch 'PASS') { Fail ("roundtrip: " + $cfg.Label) }
  Remove-Item $o1,$o2 -Force -ErrorAction SilentlyContinue
}
Remove-Item $idemSrc -Force -ErrorAction SilentlyContinue

# ----- Task 6: the broken output COMPILES (dcc64) -----
$dcc = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe'
if (Test-Path $dcc) {
  $ns   = 'System;System.Win;Winapi;Vcl;Data;Soap;Xml'
  $cdir = Join-Path $env:TEMP ('bparm_c_' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $cdir | Out-Null
  $csrc = Join-Path $cdir 'bparm_compile.pas'   # file name must equal unit name
  @'
unit bparm_compile;
interface
uses
  System.Generics.Collections;
type
  TRec = record a: Integer; end;
  TDemo = class
    procedure Go(const A: string; B: Integer; out C: Boolean);
    function Calc(const ASrc, ADest: string; AFlags: Integer): Boolean;
    procedure Swap(var A, B: Integer);
    procedure Feed(const AMap: TDictionary<string, Integer>; ACount: Integer);
    procedure Att([Ref] const A, B: TRec; C: Integer);
  end;
implementation
procedure TDemo.Go(const A: string; B: Integer; out C: Boolean);
begin
  C := B > 0;
end;
function TDemo.Calc(const ASrc, ADest: string; AFlags: Integer): Boolean;
begin
  Result := (ASrc <> ADest) and (AFlags > 0);
end;
procedure TDemo.Swap(var A, B: Integer);
var
  t: Integer;
begin
  t := A; A := B; B := t;
end;
procedure TDemo.Feed(const AMap: TDictionary<string, Integer>; ACount: Integer);
begin
end;
procedure TDemo.Att([Ref] const A, B: TRec; C: Integer);
begin
end;
end.
'@ | Set-Content $csrc -Encoding ascii
  # format IN PLACE with the break flag, then compile the result.
  & $exe $csrc --ini $ini --break-params --o $csrc | Out-Null
  & $dcc -Q "-NS$ns" "-N0$cdir" "-E$cdir" $csrc *> $null
  if ($LASTEXITCODE -ne 0) { Fail 'compile: broken param output must compile with dcc64' }
  Remove-Item $cdir -Recurse -Force -ErrorAction SilentlyContinue
} else {
  Write-Output 'break_params: (dcc64 not found -- skipping compile check)'
}

# ----- REGRESSION: a GROUPED name list that only overflows once it is expanded
# SplitParamGroup repeats the modifier per name, so `const A, B, C: T` becomes
# three items and the header GROWS. A header that fitted MaxLen on pass 1 can
# therefore cross it on pass 2, once JoinRoutineHeaders has re-joined the split
# lines: the joined line is then greedy-wrapped, and BreakRoutineParams -- which
# needs ONE balanced header line -- can no longer match it. Pass 1 breaks one
# per line, pass 2 emits a greedy two-line wrap: format(format(x)) <> format(x).
# Found on YADF's own YADF.Guard.pas (`ExtractContent`) at the repo MaxLen.
$grpIn = Join-Path $env:TEMP 'bparam_group.pas'
$g1    = Join-Path $env:TEMP 'bparam_g1.pas'
$g2    = Join-Path $env:TEMP 'bparam_g2.pas'
@'
unit probe;
interface
implementation
procedure ExtractContent(const ASource: string; const AStrings, AComments, ADirectives: TList<string>; const AIsLabel: TList<Boolean> = nil);
begin
end;
end.
'@ | Set-Content $grpIn -Encoding ascii
& $exe --ini $ini $grpIn --break-params --max-len 180 --o $g1 | Out-Null
& $exe --ini $ini $g1    --break-params --max-len 180 --o $g2 | Out-Null
$g = Get-Content $g1 -Raw
MustMatch $g '(?m)^procedure ExtractContent\(\s*$'       'group-expand: header opens with a lone ('
MustMatch $g '(?m)^\s+; const AComments\s*: TList<string>\s*$' 'group-expand: expanded group member on its own line'
if (-not (SameBytes $g1 $g2)) { Fail 'idempotent: expanded group pushes the re-joined header past MaxLen' }
$gchk = & $exe --ini $ini --check $g1 2>&1
if ("$gchk" -notmatch 'PASS') { Fail 'roundtrip/guard: expanded group header' }
Remove-Item $grpIn, $g1, $g2 -Force -ErrorAction SilentlyContinue

Finish 'break_params'
