# Fixture-based tests for BreakLoopBody/BreakWithBody/BreakIfBody
# (--break-loop / --break-with / --break-if, all default OFF). A single-line
# control statement gets its body forced onto its own indented line when the
# governing flag is on; default output is unchanged. Exit 0 = pass, 1 = fail.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
$ini = Get-RepoIni   # pin config: personal %APPDATA% profile must not affect tests
Assert-ToolOrSkip 'break_control' $exe

# ----- Task 1: the three flags are wired onto every surface -----
$help = & $exe --help 2>&1 | Out-String
MustMatch $help '--break-loop'  'help lists --break-loop'
MustMatch $help '--break-with'  'help lists --break-with'
MustMatch $help '--break-if'    'help lists --break-if'

# Generated default INI carries the three keys (table-driven template).
$tmpIni = Join-Path $env:TEMP 'bctl.ini'
Remove-Item $tmpIni -Force -ErrorAction SilentlyContinue
& $exe --ini $tmpIni --help | Out-Null   # --ini creates the template if absent
if (-not (Test-Path $tmpIni)) { & $exe --ini $tmpIni --stdout 2>&1 | Out-Null }
$iniTxt = if (Test-Path $tmpIni) { Get-Content $tmpIni -Raw } else { '' }
MustMatch $iniTxt 'BreakLoopBody'  'ini template has BreakLoopBody'
MustMatch $iniTxt 'BreakWithBody'  'ini template has BreakWithBody'
MustMatch $iniTxt 'BreakIfBody'    'ini template has BreakIfBody'
Remove-Item $tmpIni -Force -ErrorAction SilentlyContinue

# A --break-loop run is ACCEPTED (no "unknown option") even before the pass
# exists; behavior assertions arrive in Task 2/3.
$probe = Join-Path $env:TEMP 'bctl_probe.pas'
@'
unit p; interface implementation
procedure Go; var k: Integer; begin k := 0; while k < 3 do Inc(k); end;
end.
'@ | Set-Content $probe -Encoding ascii
$err = & $exe --ini $ini $probe --break-loop --stdout 2>&1 | Out-String
MustNotMatch $err 'unknown option'  '--break-loop accepted'
Remove-Item $probe -Force -ErrorAction SilentlyContinue

# ----- Task 2: for/while/with do-split (comparison-based; robust to YADF default layout) -----
# Format a procedure body (one or more statement lines) with the given flags; return full output.
function FmtStr([string]$bodyLines, [string]$flags) {
  $u = @(
    'unit probe;'
    'interface'
    'implementation'
    'procedure Demo;'
    'var'
    '  k, i, Sum, a, b: Integer;'
    'begin'
    $bodyLines
    'end;'
    'end.'
  ) -join "`r`n"
  $src = Join-Path $env:TEMP 'bctl_probe_in.pas'
  $out = Join-Path $env:TEMP 'bctl_probe_out.pas'
  Set-Content -Path $src -Value $u -Encoding ascii
  $argv = @($flags -split ' ' | Where-Object { $_ -ne '' })
  & $exe --ini $ini $src @argv --o $out | Out-Null
  $t = Get-Content $out -Raw
  Remove-Item $src,$out -Force -ErrorAction SilentlyContinue
  return $t
}

# while: splits ON, stays inline OFF (proves the flag caused the split).
$wOn  = FmtStr '  while k > 0 do Dec(k);' '--break-loop'
$wOff = FmtStr '  while k > 0 do Dec(k);' '--no-break-loop'
MustMatch $wOn  '(?m)do\s*$'         'loop on: header ends at do'
MustMatch $wOn  '(?m)^\s+Dec\(k\);'  'loop on: while body on its own line'
MustMatch $wOff '(?m)do Dec\(k\);'   'loop off: while body stays inline (default)'

# for: body splits under --break-loop.
$fOn = FmtStr '  for i := 0 to 9 do Sum := Sum + i;' '--break-loop'
# NOTE: regex has no space before `:=` -- YADF's default assignment-operator
# spacing (unrelated to this pass) always normalizes `X := Y` to `X:= Y`.
MustMatch $fOn '(?m)^\s+Sum:= Sum \+ i;' 'loop on: for body on its own line'

# with: splits under --break-with; NOT under --break-loop (cross-flag isolation).
$withW    = FmtStr '  with Rec do a := 1;' '--break-with'
$withLoop = FmtStr '  with Rec do a := 1;' '--break-loop'
$withOff  = FmtStr '  with Rec do a := 1;' '--no-break-with --no-break-loop'
# NOTE: regex has no space before `:=` -- YADF's default assignment-operator
# spacing (unrelated to this pass) always normalizes `X := Y` to `X:= Y`.
MustMatch $withW '(?m)^\s+a:= 1;' 'with on: with body on its own line'
if ($withLoop -ne $withOff) { Fail 'cross: --break-loop must NOT split a with-body' }

# --break-with must NOT split a while-body (cross-flag isolation).
$whileWith = FmtStr '  while k > 0 do Dec(k);' '--break-with'
$whileOff  = FmtStr '  while k > 0 do Dec(k);' '--no-break-loop --no-break-with'
if ($whileWith -ne $whileOff) { Fail 'cross: --break-with must NOT split a while-body' }

# NON-GOAL: a begin-block body is left to the normal pipeline (flag on == flag off).
$beginOn  = FmtStr '  while HasNext do begin Inc(a); Inc(b); end;' '--break-loop'
$beginOff = FmtStr '  while HasNext do begin Inc(a); Inc(b); end;' '--no-break-loop'
if ($beginOn -ne $beginOff) { Fail 'non-goal: begin-body loop must be untouched by --break-loop' }

# NON-GOAL: a nested control-header body is left alone (flag on == flag off).
$nestOn  = FmtStr '  while a > 0 do while b > 0 do Dec(b);' '--break-loop'
$nestOff = FmtStr '  while a > 0 do while b > 0 do Dec(b);' '--no-break-loop'
if ($nestOn -ne $nestOff) { Fail 'non-goal: nested-header loop must be untouched by --break-loop' }

# idempotency + content-preserving round-trip for each single flag.
$idemSrc = Join-Path $env:TEMP 'bctl_idem.pas'
@'
unit probe;
interface
implementation
procedure Demo;
var
  k, i, Sum, a: Integer;
begin
  while k > 0 do Dec(k);
  Sum := 0;
  for i := 0 to 9 do Sum := Sum + i;
  with Rec do a := 1;
end;
end.
'@ | Set-Content $idemSrc -Encoding ascii
foreach ($f in @('--break-loop','--break-with')) {
  $o1 = Join-Path $env:TEMP 'bctl_i1.pas'; $o2 = Join-Path $env:TEMP 'bctl_i2.pas'
  & $exe --ini $ini $idemSrc $f --o $o1 | Out-Null
  & $exe --ini $ini $o1      $f --o $o2 | Out-Null
  if ((Get-FileHash $o1).Hash -ne (Get-FileHash $o2).Hash) { Fail "idempotent: $f" }
  $chk = & $exe --ini $ini --check $o1 2>&1
  if ("$chk" -notmatch 'PASS') { Fail "roundtrip: $f" }
  Remove-Item $o1,$o2 -Force -ErrorAction SilentlyContinue
}
Remove-Item $idemSrc -Force -ErrorAction SilentlyContinue

# ----- Task 3: if/then/else split (comparison-based + direct) -----
# if/then/else: splits into four lines ON; stays inline OFF (proves the flag caused it).
$ifOn  = FmtStr '  if Sum > 0 then Inc(a) else Dec(a);' '--break-if'
$ifOff = FmtStr '  if Sum > 0 then Inc(a) else Dec(a);' '--no-break-if'
MustMatch $ifOn  '(?m)^\s*if Sum .*then\s*$' 'if on: header ends at then'
MustMatch $ifOn  '(?m)^\s+Inc\(a\)\s*$'      'if on: then-body on own line, no semicolon'
MustMatch $ifOn  '(?m)^\s*else\s*$'          'if on: else on own line'
MustMatch $ifOn  '(?m)^\s+Dec\(a\);'         'if on: else-body on own line'
MustMatch $ifOff '(?m)then Inc\(a\) else'    'if off: stays inline (default)'

# if/then, no else.
$ifNoElse = FmtStr '  if k = 0 then Inc(k);' '--break-if'
MustMatch $ifNoElse '(?m)^\s*if k .*then\s*$' 'if on: no-else header'
MustMatch $ifNoElse '(?m)^\s+Inc\(k\);'       'if on: no-else body split'

# else-if chain stays glued as one "else if ... then" header line.
$chain = FmtStr '  if k = 1 then Inc(a) else if k = 2 then Inc(b) else Dec(a);' '--break-if'
MustMatch    $chain '(?m)^\s*else if k .*then\s*$' 'chain: else-if glued'
MustMatch    $chain '(?m)^\s+Inc\(b\)\s*$'         'chain: else-if body split'
MustMatch    $chain '(?m)^\s*else\s*$'             'chain: final else on own line'
MustMatch    $chain '(?m)^\s+Dec\(a\);'            'chain: final body split'
MustNotMatch $chain '(?m)then Inc\(a\) '           'chain: no body left on the first then line'

# cross-flag isolation: --break-if must NOT split a loop body.
$loopUnderIf = FmtStr '  while k > 0 do Dec(k);' '--break-if'
$loopOff2    = FmtStr '  while k > 0 do Dec(k);' '--no-break-loop --no-break-if'
if ($loopUnderIf -ne $loopOff2) { Fail 'cross: --break-if must NOT split a loop body' }

# NON-GOAL: a nested-if body is left alone (flag on == flag off).
$nestIfOn  = FmtStr '  if a > 0 then if b > 0 then Dec(b);' '--break-if'
$nestIfOff = FmtStr '  if a > 0 then if b > 0 then Dec(b);' '--no-break-if'
if ($nestIfOn -ne $nestIfOff) { Fail 'non-goal: nested-if body must be untouched' }

# NON-GOAL: a line carrying a top-level // comment is never split (flag on == flag off).
$cmtOn  = FmtStr '  if k = 0 then Inc(k); // trailing note' '--break-if'
$cmtOff = FmtStr '  if k = 0 then Inc(k); // trailing note' '--no-break-if'
if ($cmtOn -ne $cmtOff) { Fail 'non-goal: line with top-level // must be untouched' }

# idempotency + content-preserving round-trip for --break-if.
$ifIdem = Join-Path $env:TEMP 'bctl_if.pas'
@'
unit probe;
interface
implementation
procedure Demo;
var
  a, b, k, Sum: Integer;
begin
  if Sum > 0 then Inc(a) else Dec(a);
  if k = 1 then Inc(a) else if k = 2 then Inc(b) else Dec(a);
  if k = 0 then Inc(k);
end;
end.
'@ | Set-Content $ifIdem -Encoding ascii
$o1 = Join-Path $env:TEMP 'bctl_if1.pas'; $o2 = Join-Path $env:TEMP 'bctl_if2.pas'
& $exe --ini $ini $ifIdem --break-if --o $o1 | Out-Null
& $exe --ini $ini $o1     --break-if --o $o2 | Out-Null
if ((Get-FileHash $o1).Hash -ne (Get-FileHash $o2).Hash) { Fail 'idempotent: --break-if' }
$chk = & $exe --ini $ini --check $o1 2>&1
if ("$chk" -notmatch 'PASS') { Fail 'roundtrip: --break-if' }
Remove-Item $ifIdem,$o1,$o2 -Force -ErrorAction SilentlyContinue

# ----- Task 4: all three flags together -----
$allBody = @(
  '  while k > 0 do Dec(k);'
  '  with Rec do a := 1;'
  '  if Sum > 0 then Inc(a) else Dec(a);'
) -join "`r`n"
$all = FmtStr $allBody '--break-loop --break-with --break-if'
MustMatch $all '(?m)^\s+Dec\(k\);'  'all: loop body split'
MustMatch $all '(?m)^\s+a:= 1;'     'all: with body split'
MustMatch $all '(?m)^\s*else\s*$'   'all: if/else split'

# ----- Task 4: the split output COMPILES (dcc64) -- proves valid Delphi, not just content-preserving -----
$dcc = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe'
if (Test-Path $dcc) {
  $ns   = 'System;System.Win;Winapi;Vcl;Data;Soap;Xml'
  $cdir = Join-Path $env:TEMP ('bctl_c_' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $cdir | Out-Null
  $csrc = Join-Path $cdir 'bctl_compile.pas'   # file name must equal unit name
  @'
unit bctl_compile;
interface
implementation
type
  TR = record a: Integer; end;
procedure Demo;
var
  k, i, Sum: Integer;
  r: TR;
begin
  k := 3;
  while k > 0 do Dec(k);
  Sum := 0;
  for i := 0 to 9 do Sum := Sum + i;
  with r do a := 1;
  if Sum > 0 then Inc(k) else Dec(k);
end;
end.
'@ | Set-Content $csrc -Encoding ascii
  # format IN PLACE with all three split flags, then compile the result.
  & $exe $csrc --ini $ini --break-loop --break-with --break-if --o $csrc | Out-Null
  & $dcc -Q "-NS$ns" "-N0$cdir" "-E$cdir" $csrc *> $null
  if ($LASTEXITCODE -ne 0) { Fail 'compile: split output must compile with dcc64' }
  Remove-Item $cdir -Recurse -Force -ErrorAction SilentlyContinue
} else {
  Write-Output 'break_control: (dcc64 not found -- skipping compile check)'
}

# ----- Case fidelity: --break-if must not force keyword casing (respects LowercaseKeywords) -----
# With LowercaseKeywords OFF, a source uppercase ELSE must stay ELSE after the split (the
# standalone else segment is copied from source, not a hardcoded lowercase literal).
$caseOut = FmtStr '  if Sum > 0 then Inc(a) ELSE Dec(a);' '--break-if --no-lowercase-keywords'
MustMatch $caseOut '(?m)^\s*ELSE\s*$' 'case: uppercase ELSE preserved under --no-lowercase-keywords'
# Default (LowercaseKeywords on) still lowercases it -- sanity that the default did not regress.
$caseDef = FmtStr '  if Sum > 0 then Inc(a) ELSE Dec(a);' '--break-if'
MustMatch $caseDef '(?m)^\s*else\s*$' 'case: default still lowercases else'

Finish 'break_control'
