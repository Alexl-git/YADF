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

# ----- Task 2: one component per line, operator leading -----
# Format a procedure body at a small MaxLen; return the full output.
function FmtBody([string]$bodyLines, [string]$flags, [int]$maxLen = 60) {
  $u = @(
    'unit probe;'
    'interface'
    'implementation'
    'procedure Demo;'
    'var'
    '  AlphaFlagIsLong, BetaFlagIsLong, GammaFlagIsLong, DeltaFlagIsLong: Boolean;'
    '  Aa, Bb, Total: Integer;'
    'begin'
    $bodyLines
    'end;'
    'end.'
  ) -join "`r`n"
  $src = Join-Path $env:TEMP 'bexpr_in.pas'
  $out = Join-Path $env:TEMP 'bexpr_out.pas'
  Set-Content -Path $src -Value $u -Encoding ascii
  $argv = @($flags -split ' ' | Where-Object { $_ -ne '' })
  & $exe --ini $ini $src --max-len $maxLen @argv --o $out | Out-Null
  $t = Get-Content $out -Raw
  Remove-Item $src,$out -Force -ErrorAction SilentlyContinue
  return $t
}

# A FLAT condition (no parens): one operand per line, operator leading.
$flat = FmtBody '  if AlphaFlagIsLong and BetaFlagIsLong and GammaFlagIsLong and DeltaFlagIsLong then Writeln(1);' '--break-expr'
MustMatch $flat '(?m)^\s+if AlphaFlagIsLong\s*$'  'flat: head is the first operand alone'
MustMatch $flat '(?m)^\s+and BetaFlagIsLong\s*$'  'flat: and leads component 2'
MustMatch $flat '(?m)^\s+and GammaFlagIsLong\s*$' 'flat: and leads component 3'
# The last component still carries the trailing `then` -- moving it to its own
# line is Task 3's job, so assert the component, not the end of line.
MustMatch $flat '(?m)^\s+and DeltaFlagIsLong then\b' 'flat: and leads component 4'

# RECURSION: a component that still overflows breaks again, ONE STEP DEEPER.
# Indent=2, so top-level components sit at 4 and their children at 6.
$deep = FmtBody '  if (Aa > 0) or (AlphaFlagIsLong and BetaFlagIsLong and GammaFlagIsLong and DeltaFlagIsLong) then Writeln(1);' '--break-expr' 46
$orLine  = ($deep -split "`r?`n" | Where-Object { $_ -match '^\s+or \(AlphaFlagIsLong' } | Select-Object -First 1)
$subLine = ($deep -split "`r?`n" | Where-Object { $_ -match '^\s+and GammaFlagIsLong' } | Select-Object -First 1)
if (-not $orLine)  { Fail 'recursion: no top-level or component line' }
if (-not $subLine) { Fail 'recursion: over-long component was not broken again' }
$orInd  = ($orLine  -replace '\S.*$','').Length
$subInd = ($subLine -replace '\S.*$','').Length
if ($subInd -le $orInd) { Fail "recursion: sub-component indent $subInd must be deeper than parent $orInd" }

# A parenthesised condition: the GROUPS stay whole, only the top-level or breaks.
# MaxLen 70 leaves room for the trailing `then Writeln(1);` that rides the last
# component until Task 3 moves it; at 60 the component overflows by one char and
# the greedy fallback splits it, which is a different behaviour under test.
$paren = FmtBody '  if (AlphaFlagIsLong and BetaFlagIsLong) or (GammaFlagIsLong and DeltaFlagIsLong) then Writeln(1);' '--break-expr' 70
MustMatch $paren '(?m)^\s+if \(AlphaFlagIsLong and BetaFlagIsLong\)\s*$' 'paren: first group whole on the head line'
MustMatch $paren '(?m)^\s+or \(GammaFlagIsLong and DeltaFlagIsLong\) then Writeln\(1\);\s*$' 'paren: second group whole, or leading'
# Control: the greedy breaker shatters that same group at the same MaxLen.
$parenGreedy = FmtBody '  if (AlphaFlagIsLong and BetaFlagIsLong) or (GammaFlagIsLong and DeltaFlagIsLong) then Writeln(1);' '--no-break-expr' 70
MustNotMatch $parenGreedy '(?m)^\s+or \(GammaFlagIsLong and DeltaFlagIsLong\)' 'paren: control -- greedy does NOT keep the group whole'

# NO GREEDY PACKING: three top-level components must give three lines even
# though the first two would comfortably share one.
$three = FmtBody '  if (Aa > 0) or (Bb > 0) or (AlphaFlagIsLong and BetaFlagIsLong and GammaFlagIsLong) then Writeln(1);' '--break-expr'
MustMatch $three '(?m)^\s+if \(Aa > 0\)\s*$'  'nogreedy: component 1 alone on its line'
MustMatch $three '(?m)^\s+or \(Bb > 0\)\s*$'  'nogreedy: component 2 alone on its line'

# Arithmetic breaks by the same rule.
$arith = FmtBody '  Total := AlphaFlagIsLongValue + BetaFlagIsLongValue + GammaFlagIsLongValue + DeltaValue;' '--break-expr'
MustMatch $arith '(?m)^\s+\+ BetaFlagIsLongValue\s*$'  'arith: + leads the continuation'

# Option OFF keeps today's greedy output (control: proves the flag caused it).
$greedy = FmtBody '  if (Aa > 0) or (Bb > 0) or (AlphaFlagIsLong and BetaFlagIsLong and GammaFlagIsLong) then Writeln(1);' '--no-break-expr'
if ($greedy -eq $three) { Fail 'control: --break-expr output must differ from the greedy default' }

# A line that already fits is untouched.
$short = FmtBody '  if Aa > 0 then Writeln(1);' '--break-expr'
MustMatch $short '(?m)^\s+if Aa > 0 then Writeln\(1\);\s*$' 'short: fitting line untouched'

# ----- Task 3: trailing then / do on their own line, at the header column -----
# NOTE on the fixture shape: the body sits on its own line already. The keyword
# split fires only when `then`/`do` is the header line's LAST token -- moving
# the *body* off the header line is BreakIfBody's job, not this option's (spec
# "Interactions": the two compose, neither reads the other's output).

# 'then' must land in EXACTLY the same column as its 'if'.
$thenBody = @(
  '  if (AlphaFlagIsLong and BetaFlagIsLong) or (GammaFlagIsLong and DeltaFlagIsLong) then'
  '    Writeln(1);'
) -join "`r`n"
$thenOut = FmtBody $thenBody '--break-expr'
$ifCol   = ($thenOut -split "`r?`n" | Where-Object { $_ -match '^\s*if \(' }     | Select-Object -First 1) -replace '\S.*$',''
$thenCol = ($thenOut -split "`r?`n" | Where-Object { $_ -match '^\s*then\s*$' } | Select-Object -First 1) -replace '\S.*$',''
if (-not $thenCol) { Fail 'then: no standalone then line' }
if ($ifCol.Length -ne $thenCol.Length) { Fail "then: column $($thenCol.Length) must equal if column $($ifCol.Length)" }
MustMatch $thenOut '(?m)^\s+or \(GammaFlagIsLong and DeltaFlagIsLong\)\s*$' 'then: last component keeps no trailing keyword'

# 'do' must land in EXACTLY the same column as its 'while'.
$doBody = @(
  '  while (AlphaFlagIsLong and BetaFlagIsLong) or (GammaFlagIsLong and DeltaFlagIsLong) do'
  '    Writeln(1);'
) -join "`r`n"
$doOut  = FmtBody $doBody '--break-expr'
$whCol  = ($doOut -split "`r?`n" | Where-Object { $_ -match '^\s*while \(' } | Select-Object -First 1) -replace '\S.*$',''
$doCol  = ($doOut -split "`r?`n" | Where-Object { $_ -match '^\s*do\s*$' }   | Select-Object -First 1) -replace '\S.*$',''
if (-not $doCol) { Fail 'do: no standalone do line' }
if ($whCol.Length -ne $doCol.Length) { Fail "do: column $($doCol.Length) must equal while column $($whCol.Length)" }

# 'until' LEADS its condition -- nothing moves, and the ';' stays on the last line.
$untilBody = @(
  '  repeat'
  '    Writeln(1);'
  '  until (AlphaFlagIsLong and BetaFlagIsLong) or (GammaFlagIsLong and DeltaFlagIsLong);'
) -join "`r`n"
$untilOut = FmtBody $untilBody '--break-expr'
MustMatch    $untilOut '(?m)^\s+until \(AlphaFlagIsLong and BetaFlagIsLong\)\s*$' 'until: keeps its leading position'
MustMatch    $untilOut '(?m)^\s+or \(GammaFlagIsLong and DeltaFlagIsLong\);\s*$'  'until: ; stays on the last component'
MustNotMatch $untilOut '(?m)^\s*until\s*$'                                        'until: never gets a lone keyword line'

# Case fidelity: an uppercase THEN survives when LowercaseKeywords is off.
$caseBody = @(
  '  if (AlphaFlagIsLong and BetaFlagIsLong) or (GammaFlagIsLong and DeltaFlagIsLong) THEN'
  '    Writeln(1);'
) -join "`r`n"
$caseOut = FmtBody $caseBody '--break-expr --no-lowercase-keywords'
MustMatch $caseOut '(?m)^\s*THEN\s*$' 'case: uppercase THEN preserved'

# A header line that already fits is untouched -- the keyword does NOT move.
$fitHdr = @(
  '  if Aa > 0 then'
  '    Writeln(1);'
) -join "`r`n"
$fitOut = FmtBody $fitHdr '--break-expr'
MustMatch $fitOut '(?m)^\s+if Aa > 0 then\s*$' 'then: fitting header keeps its keyword'

# ----- Task 4: idempotency + content-preserving round-trip -----
$idemSrc = Join-Path $env:TEMP 'bexpr_idem.pas'
@'
unit probe;
interface
implementation
procedure Demo;
var
  AlphaFlagIsLong, BetaFlagIsLong, GammaFlagIsLong, DeltaFlagIsLong: Boolean;
  Aa, Bb, Total: Integer;
begin
  if (AlphaFlagIsLong and BetaFlagIsLong) or (GammaFlagIsLong and DeltaFlagIsLong) then
    Writeln(1);
  while (AlphaFlagIsLong and BetaFlagIsLong) or (GammaFlagIsLong and DeltaFlagIsLong) do
    Writeln(2);
  Total := 1 + 2 + 3;
  repeat
    Writeln(3);
  until (AlphaFlagIsLong and BetaFlagIsLong) or (GammaFlagIsLong and DeltaFlagIsLong);
end;
end.
'@ | Set-Content $idemSrc -Encoding ascii

$o1 = Join-Path $env:TEMP 'bexpr_i1.pas'; $o2 = Join-Path $env:TEMP 'bexpr_i2.pas'
& $exe --ini $ini $idemSrc --break-expr --max-len 60 --o $o1 | Out-Null
& $exe --ini $ini $o1      --break-expr --max-len 60 --o $o2 | Out-Null
if ((Get-FileHash $o1).Hash -ne (Get-FileHash $o2).Hash) { Fail 'idempotent: --break-expr' }
$chk = & $exe --ini $ini --check $o1 2>&1
if ("$chk" -notmatch 'PASS') { Fail 'roundtrip: --break-expr' }

# ----- Task 4: the body-break flags must not disturb the component layout -----
# BreakControlBodies runs another ReindentByDepth AFTER the deferred
# BreakLongLines, but only when one of --break-if / --break-loop / --break-with
# is on. Nothing else in the suite locks that down, so a change there could
# silently re-indent the lone `then` line. Byte-compare all three flag sets --
# the repo ini leaves those three ON, so the explicit --no- run is what actually
# exercises the branch where that second ReindentByDepth does NOT fire.
$o3 = Join-Path $env:TEMP 'bexpr_i3.pas'; $o4 = Join-Path $env:TEMP 'bexpr_i4.pas'
& $exe --ini $ini $idemSrc --break-expr --break-if --break-loop --break-with --max-len 60 --o $o3 | Out-Null
& $exe --ini $ini $idemSrc --break-expr --no-break-if --no-break-loop --no-break-with --max-len 60 --o $o4 | Out-Null
$a = Get-Content $o1 -Raw
$b = Get-Content $o3 -Raw
$c = Get-Content $o4 -Raw
if ($a -ne $b) { Fail 'cross: body-break flags must not disturb the component layout' }
if ($a -ne $c) { Fail 'cross: disabling the body-break flags must not disturb the component layout' }
Remove-Item $o1,$o2,$o3,$o4 -Force -ErrorAction SilentlyContinue

# ----- Task 4: the broken output COMPILES (dcc64) -----
$dcc = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe'
if (Test-Path $dcc) {
  $ns   = 'System;System.Win;Winapi;Vcl;Data;Soap;Xml'
  $cdir = Join-Path $env:TEMP ('bexpr_c_' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $cdir | Out-Null
  $csrc = Join-Path $cdir 'bexpr_compile.pas'   # file name must equal unit name
  Copy-Item $idemSrc $csrc -Force
  (Get-Content $csrc -Raw).Replace('unit probe;', 'unit bexpr_compile;') | Set-Content $csrc -Encoding ascii
  & $exe $csrc --ini $ini --break-expr --max-len 60 --o $csrc | Out-Null
  & $dcc -Q "-NS$ns" "-N0$cdir" "-E$cdir" $csrc *> $null
  if ($LASTEXITCODE -ne 0) { Fail 'compile: broken expression output must compile with dcc64' }
  Remove-Item $cdir -Recurse -Force -ErrorAction SilentlyContinue
} else {
  Write-Output 'break_expr: (dcc64 not found -- skipping compile check)'
}
Remove-Item $idemSrc -Force -ErrorAction SilentlyContinue

Finish 'break_expr'
