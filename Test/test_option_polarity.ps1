# Option POLARITY suite: every boolean layout option that changes line
# structure, tested in BOTH directions against its SPEC, not against YADF's own
# output.
#
# WHY: CollapseShortBlocks=false silently did nothing for a whole release
# (fixed in cbd88bf) and every review missed it, because the goldens were
# recorded from YADF's output and so blessed it. Each expectation below comes
# from docs\help-site\options\<id>.md (= the yadf.ini template comment):
#   ON  + input written in the OFF shape -> output must be the ON shape;
#   OFF + input written in the ON shape  -> output must be the OFF shape
#                                           (or unchanged, when OFF = preserve).
# Every run also checks exit 0 / no guard decline, idempotence (format the
# output again = same bytes) and that the output still compiles (dcc64).
#
# Config: each run uses a fresh temp INI holding ONLY the option(s) under test,
# so every other option is the built-in default and the owner's %APPDATA%
# profile cannot leak in.
#
# KNOWN-GAP: a case whose spec YADF does not meet is kept, carries a Gap note,
# and is printed in the KNOWN-GAP list on every run instead of failing the
# suite. A known gap that starts PASSING fails the suite, so the list cannot
# go stale: remove the Gap note once the engine is fixed.
# QUESTION: spec directions too ambiguous to assert are listed (not asserted).
#
# Fixtures: Test\Cases\polarity\*.pas (compilable standalone; excluded from
# the byte-golden suite on purpose -- they must never be blessed by output).
# Exit 0 = pass, 1 = failures, 2 = skip (no exe).
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
Assert-ToolOrSkip 'option_polarity' $exe
$fixDir = Join-Path $PSScriptRoot 'Cases\polarity'
$haveDcc = Test-Path (Get-Dcc64)

$work = Join-Path $env:TEMP ('polarity_' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($work) | Out-Null
$dcuDir = Join-Path $work 'dcu'
[IO.Directory]::CreateDirectory($dcuDir) | Out-Null

# --- the cases --------------------------------------------------------------
# Fix  = fixture base name; Set = INI keys for this run (nothing else is set);
# Must / Not = regexes the output must / must not match; Show = regex picking
# the output lines printed as "actual" for a known gap; Gap = known-gap note.
$T = 'true'; $F = 'false'
$cases = @(
  # ReflowLines (default true): ON drops non-essential user breaks and fills
  # MaxLen; OFF preserves the original line breaks, long lines left as-is.
  @{ Id = 'ReflowLines ON: mid-expression hand break is joined'; Fix = 'polarity_reflow'; Set = @{ ReflowLines = $T }
     In = 'Alpha:= Sum3(1,<NL>2, 3);'; Want = 'Alpha:= Sum3(1, 2, 3);'
     Must = @('(?m)^\s*Alpha:= Sum3\(1, 2, 3\);\r?$') }
  @{ Id = 'ReflowLines ON: a break between statements is kept'; Fix = 'polarity_reflow'; Set = @{ ReflowLines = $T }
     In = 'Beta:= Alpha;<NL>Gamma:= Beta;'; Want = 'two lines'
     Must = @('(?m)^\s*Beta\s*:= Alpha;\r?\n\s*Gamma:= Beta;\r?$') }
  @{ Id = 'ReflowLines ON: a line over MaxLen is wrapped'; Fix = 'polarity_reflow'; Set = @{ ReflowLines = $T }
     In = 'Delta:= <195-char sum>'; Want = 'no line > 180'
     Not = @('(?m)^[^\r\n]{181,}') }
  @{ Id = 'ReflowLines OFF: mid-expression hand break is preserved'; Fix = 'polarity_reflow'; Set = @{ ReflowLines = $F }
     In = 'Alpha:= Sum3(1,<NL>2, 3);'; Want = 'break kept'; Show = 'Alpha:= Sum3'
     Must = @('(?m)^\s*Alpha:= Sum3\(1,\r?\n\s*2, 3\);\r?$') }
  @{ Id = 'ReflowLines OFF: a break between statements is kept'; Fix = 'polarity_reflow'; Set = @{ ReflowLines = $F }
     In = 'Beta:= Alpha;<NL>Gamma:= Beta;'; Want = 'two lines'
     Must = @('(?m)^\s*Beta\s*:= Alpha;\r?\n\s*Gamma:= Beta;\r?$') }
  @{ Id = 'ReflowLines OFF: a line over MaxLen is left as-is'; Fix = 'polarity_reflow'; Set = @{ ReflowLines = $F }
     In = 'Delta:= <195-char sum on one line>'; Want = 'line unchanged'; Show = '^\s*(Alpha,|Beta,?|\);)\s*$|^\s*Delta:='
     Must = @('(?m)^\s*Delta:= Sum3\(Alpha, Beta, Gamma\) \+ [^\r\n]* \+ Sum3\(Alpha, Beta, Beta\);\r?$') }

  # PackShortBodies (default false): ON pulls a short loop/if body or case arm
  # onto its header line.
  @{ Id = 'PackShortBodies ON: for body packed'; Fix = 'polarity_pack'; Set = @{ PackShortBodies = $T }
     In = 'for I:= 0 to N do<NL>Inc(PkA);'; Want = 'one line'
     Must = @('(?m)^\s*for I:= 0 to N do Inc\(PkA\);\r?$') }
  @{ Id = 'PackShortBodies ON: if body packed'; Fix = 'polarity_pack'; Set = @{ PackShortBodies = $T }
     In = 'if PkA > 0 then<NL>Dec(PkB);'; Want = 'one line'
     Must = @('(?m)^\s*if PkA > 0 then Dec\(PkB\);\r?$') }
  @{ Id = 'PackShortBodies ON: case arm packed'; Fix = 'polarity_pack'; Set = @{ PackShortBodies = $T }
     In = '0:<NL>Inc(PkC);'; Want = '0: Inc(PkC);'
     Must = @('(?m)^\s*0: Inc\(PkC\);\r?$') }
  @{ Id = 'PackShortBodies OFF: bodies on their own line stay there'; Fix = 'polarity_pack'; Set = @{ PackShortBodies = $F }
     In = 'for/if/case-arm with the body on its own line'; Want = 'unchanged'
     Must = @('(?m)^\s*for I:= 0 to N do\r?\n\s+Inc\(PkA\);\r?$', '(?m)^\s*if PkA > 0 then\r?\n\s+Dec\(PkB\);\r?$', '(?m)^\s*0:\r?\n\s+Inc\(PkC\);\r?$') }

  # CollapseShortBlocks (default false): ON folds a short control begin..end
  # onto one line when it fits MaxLen; OFF EXPANDS a one-line block.
  @{ Id = 'CollapseShortBlocks ON: "then begin" block folds'; Fix = 'polarity_collapse'; Set = @{ CollapseShortBlocks = $T }
     In = 'if C then begin<NL>CbA:= 1;<NL>CbB:= 2;<NL>end;'; Want = 'if C then begin CbA:= 1; CbB:= 2; end;'; Show = '(if C then begin|CbA:= 1|CbB:= 2)'
     Must = @('(?m)^\s*if C then begin CbA:= 1; CbB:= 2; end;\r?$') }
  @{ Id = 'CollapseShortBlocks ON: begin-on-own-line block folds'; Fix = 'polarity_collapse'; Set = @{ CollapseShortBlocks = $T }
     In = 'if not C then<NL>begin<NL>CbE:= 1;<NL>CbF:= 2;<NL>end;'; Want = 'one line'
     Must = @('(?m)^\s*if not C then begin CbE:= 1; CbF:= 2; end;\r?$') }
  @{ Id = 'CollapseShortBlocks ON: one-line block stays folded'; Fix = 'polarity_collapse'; Set = @{ CollapseShortBlocks = $T }
     In = 'while CbC > 0 do begin Dec(CbC); CbD:= CbC; end;'; Want = 'unchanged'
     Must = @('(?m)^\s*while CbC > 0 do begin Dec\(CbC\); CbD:= CbC; end;\r?$') }
  @{ Id = 'CollapseShortBlocks ON + block too long for MaxLen stays expanded'; Fix = 'polarity_collapse'; Set = @{ CollapseShortBlocks = $T }
     In = '3-statement block, ~225 chars folded'; Want = 'expanded'
     Must = @('(?m)^\s*if C then begin\r?\n\s+LongNameNumberOne\s*:=')
     Not = @('begin LongNameNumberOne', '(?m)^[^\r\n]{181,}') }
  @{ Id = 'CollapseShortBlocks OFF: one-line block expands'; Fix = 'polarity_collapse'; Set = @{ CollapseShortBlocks = $F }
     In = 'while CbC > 0 do begin Dec(CbC); CbD:= CbC; end;'; Want = 'one statement per line'
     Must = @('(?m)^\s*while CbC > 0 do begin\r?\n\s+Dec\(CbC\);\r?\n\s+CbD:= CbC;\r?\n\s*end;\r?$') }
  @{ Id = 'CollapseShortBlocks OFF: expanded block stays expanded'; Fix = 'polarity_collapse'; Set = @{ CollapseShortBlocks = $F }
     In = 'if C then begin<NL>CbA:= 1;<NL>CbB:= 2;<NL>end;'; Want = 'unchanged'
     Must = @('(?m)^\s*if C then begin\r?\n\s+CbA:= 1;\r?\n\s+CbB:= 2;\r?\n\s*end;\r?$', '(?m)^\s*if not C then\r?\n\s*begin\r?\n\s+CbE:= 1;\r?\n\s+CbF:= 2;\r?\n\s*end;\r?$') }

  # BreakIfBody (default false): ON forces then/else bodies of a one-line if
  # onto their own lines; OFF does not force (CLI: "keep ... inline").
  @{ Id = 'BreakIfBody ON: then/else bodies broken'; Fix = 'polarity_breakbody'; Set = @{ BreakIfBody = $T }
     In = 'if C then IfA:= 1 else IfA:= 2;'; Want = 'if C then / IfA:= 1 / else / IfA:= 2;'
     Must = @('(?m)^\s*if C then\r?\n\s+IfA:= 1\r?\n\s*else\r?\n\s+IfA:= 2;\r?$') }
  @{ Id = 'BreakIfBody OFF: one-line if kept inline, broken if kept broken'; Fix = 'polarity_breakbody'; Set = @{ BreakIfBody = $F }
     In = 'if C then IfA:= 1 else IfA:= 2; + broken IfB'; Want = 'unchanged'
     Must = @('(?m)^\s*if C then IfA:= 1 else IfA:= 2;\r?$', '(?m)^\s*if C then\r?\n\s+IfB:= 1\r?\n\s*else\r?\n\s+IfB:= 2;\r?$') }

  # BreakLoopBody (default false).
  @{ Id = 'BreakLoopBody ON: while/for bodies broken, commented body left alone'; Fix = 'polarity_breakbody'; Set = @{ BreakLoopBody = $T }
     In = 'while LpA > 0 do Dec(LpA); / for ... do Inc(LpB);'; Want = 'body on its own line'
     Must = @('(?m)^\s*while LpA > 0 do\r?\n\s+Dec\(LpA\);\r?$', '(?m)^\s*for I:= 0 to 3 do\r?\n\s+Inc\(LpB\);\r?$', '(?m)^\s*while LpE > 0 do Dec\(LpE\); // keep\r?$') }
  @{ Id = 'BreakLoopBody OFF: inline kept inline, broken kept broken'; Fix = 'polarity_breakbody'; Set = @{ BreakLoopBody = $F }
     In = 'LpA/LpB inline, LpC/LpD broken'; Want = 'unchanged'
     Must = @('(?m)^\s*while LpA > 0 do Dec\(LpA\);\r?$', '(?m)^\s*for I:= 0 to 3 do Inc\(LpB\);\r?$', '(?m)^\s*while LpC > 0 do\r?\n\s+Dec\(LpC\);\r?$', '(?m)^\s*for I:= 0 to 3 do\r?\n\s+Inc\(LpD\);\r?$') }

  # BreakWithBody (default false).
  @{ Id = 'BreakWithBody ON: with body broken'; Fix = 'polarity_breakbody'; Set = @{ BreakWithBody = $T }
     In = 'with R do WtA:= IfA;'; Want = 'body on its own line'
     Must = @('(?m)^\s*with R do\r?\n\s+WtA:= IfA;\r?$') }
  @{ Id = 'BreakWithBody OFF: inline kept inline, broken kept broken'; Fix = 'polarity_breakbody'; Set = @{ BreakWithBody = $F }
     In = 'WtA inline, WtB broken'; Want = 'unchanged'
     Must = @('(?m)^\s*with R do WtA:= IfA;\r?$', '(?m)^\s*with R do\r?\n\s+WtB:= IfB;\r?$') }

  # BreakParamsOnePerLine (default false).
  @{ Id = 'BreakParamsOnePerLine ON: one parameter per line, groups split, calls untouched'; Fix = 'polarity_params'; Set = @{ BreakParamsOnePerLine = $T }
     In = 'procedure ParamsInline(const PA: string; PB: Integer); / (const PC, PD: string)'; Want = 'one per line, const repeated'
     Must = @('(?m)^\s*const PA: string\r?$', '(?m)^\s*const PC: string\r?$', '(?m)^\s*;?\s*const PD: string\r?$', '(?m)^\s*ParamsInline\(''a'', 1\);\r?$')
     Not = @('(?m)^[^\r\n]*PA: string[^\r\n]*PB: Integer', '\(const PC, PD') }
  @{ Id = 'BreakParamsOnePerLine OFF: inline lists stay inline'; Fix = 'polarity_params'; Set = @{ BreakParamsOnePerLine = $F }
     In = 'ParamsInline / ParamsGrouped on one line'; Want = 'unchanged'
     Must = @('(?m)^procedure ParamsInline\(const PA: string; PB: Integer\);\r?$', '(?m)^procedure ParamsGrouped\(const PC, PD: string\);\r?$') }
  # Owner decision Q4 (SPEC-2026-11-01): OFF joins a list written one per line
  # when it fits MaxLen, with no space after "(".
  @{ Id = 'BreakParamsOnePerLine OFF: a list written one per line is joined, no space after "("'; Fix = 'polarity_params'; Set = @{ BreakParamsOnePerLine = $F }
     In = 'procedure ParamsSpread(<NL>const PE: string;<NL>PF: Integer);'; Want = 'procedure ParamsSpread(const PE: string; PF: Integer);'
     Must = @('(?m)^procedure ParamsSpread\(const PE: string; PF: Integer\);\r?$')
     Not = @('ParamsSpread\(\s+const', '(?m)^\s*const PE: string;\s*$') }

  # BreakLongExpressions (default true): ON = one top-level component per line,
  # operator leading, then on its own line; OFF = greedy packing.
  @{ Id = 'BreakLongExpressions ON: long condition one component per line'; Fix = 'polarity_breakexpr'; Set = @{ BreakLongExpressions = $T }
     In = 'if (V[0] > 100) and ... and (V[10] > 1100) then  (one line, > 180)'; Want = 'one "and" per line, then on its own line'
     Must = @('(?m)^\s+and \(V\[1\] > 200\)\r?$', '(?m)^\s+and \(V\[10\] > 1100\)\r?\n\s*then\r?$')
     Not = @('(?m)^[^\r\n]*\band \(V[^\r\n]*\band \(V') }
  @{ Id = 'BreakLongExpressions ON: lines that already fit are not touched'; Fix = 'polarity_breakexpr'; Set = @{ BreakLongExpressions = $T }
     In = 'the W condition already one component per line'; Want = 'still one per line'
     Not = @('(?m)^[^\r\n]*\band \(W[^\r\n]*\band \(W') }
  @{ Id = 'BreakLongExpressions OFF: greedy packing (one-line input)'; Fix = 'polarity_breakexpr'; Set = @{ BreakLongExpressions = $F }
     In = 'the V condition on one line'; Want = 'several components per line, none > 180'
     Must = @('(?m)^[^\r\n]*\(V\[0\][^\r\n]*\band \(V\[1\][^\r\n]*\band \(V\[2\]')
     Not = @('(?m)^[^\r\n]{181,}') }
  @{ Id = 'BreakLongExpressions OFF: greedy packing (one-per-line input)'; Fix = 'polarity_breakexpr'; Set = @{ BreakLongExpressions = $F }
     In = 'the W condition one component per line'; Want = 'repacked greedily'
     Must = @('(?m)^[^\r\n]*\(W\[0\][^\r\n]*\band \(W\[1\][^\r\n]*\band \(W\[2\]') }

  # BreakCaseLabels (default false).
  @{ Id = 'BreakCaseLabels ON: multi-label arm split, statement duplicated'; Fix = 'polarity_caselabels'; Set = @{ BreakCaseLabels = $T }
     In = '1, 2, 3: Inc(CsA);'; Want = '1: Inc(CsA); / 2: ... / 3: ...'
     Must = @('(?m)^\s*1: Inc\(CsA\);\r?\n\s*2: Inc\(CsA\);\r?\n\s*3: Inc\(CsA\);\r?$') }
  @{ Id = 'BreakCaseLabels OFF: multi-label arm kept, single arms not merged'; Fix = 'polarity_caselabels'; Set = @{ BreakCaseLabels = $F }
     In = '1, 2, 3: Inc(CsA); 5: Inc(CsB); 6: Inc(CsB);'; Want = 'unchanged'
     Must = @('(?m)^\s*1, 2, 3: Inc\(CsA\);\r?$', '(?m)^\s*5\s*: Inc\(CsB\);\r?$', '(?m)^\s*6\s*: Inc\(CsB\);\r?$') }

  # SplitMultiVarDecls (default true).
  @{ Id = 'SplitMultiVarDecls ON: grouped decl split'; Fix = 'polarity_splitvars'; Set = @{ SplitMultiVarDecls = $T }
     In = 'SvA, SvB: Integer;'; Want = 'SvA: Integer; / SvB: Integer;'
     Must = @('(?m)^\s*SvA\s*: Integer;\r?\n\s*SvB\s*: Integer;\r?$') }
  @{ Id = 'SplitMultiVarDecls OFF: grouped decl kept, split decls unchanged'; Fix = 'polarity_splitvars'; Set = @{ SplitMultiVarDecls = $F }
     In = 'SvA, SvB: Integer; SvC/SvD separate'; Want = 'unchanged'
     Must = @('(?m)^\s*SvA, SvB\s*: Integer;\r?$', '(?m)^\s*SvC\s*: Integer;\r?\n\s*SvD\s*: Integer;\r?$') }

  # UsesAlwaysBreak (default true) / UsesCommaLast (default false).
  @{ Id = 'UsesAlwaysBreak ON: one-line uses broken comma-first'; Fix = 'polarity_uses'; Set = @{ UsesAlwaysBreak = $T }
     In = 'uses SysUtils, Classes;'; Want = 'one unit per line, leading comma, ; alone'
     Must = @('(?m)^uses\r?\n\s+SysUtils\r?\n\s*, Classes\r?\n\s*;\r?$') }
  @{ Id = 'UsesAlwaysBreak ON: commas and ; at the column of "uses" (spec example)'; Fix = 'polarity_uses'; Set = @{ UsesAlwaysBreak = $T }
     In = 'uses SysUtils, Classes;'; Want = 'uses / "  SysUtils" / ", Classes" / ";"'; Show = '^\s*(uses|SysUtils|, Classes|;)\s*$'
     Must = @('(?m)^uses\r?\n  SysUtils\r?\n, Classes\r?\n;\r?$')
     Gap = 'wrong output vs spec example (cosmetic): comma and ; are indented to the unit column ("  , Classes" / "  ;"), the spec shows them under "uses"' }
  @{ Id = 'UsesAlwaysBreak OFF: broken uses that fits is joined'; Fix = 'polarity_uses'; Set = @{ UsesAlwaysBreak = $F }
     In = 'uses<NL>Math,<NL>Types;'; Want = 'uses Math, Types;'
     Must = @('(?m)^uses Math, Types;\r?$', '(?m)^uses SysUtils, Classes;\r?$') }
  @{ Id = 'UsesCommaLast ON: broken uses comma-last'; Fix = 'polarity_uses'; Set = @{ UsesCommaLast = $T }
     In = 'uses SysUtils, Classes; (broken by UsesAlwaysBreak default)'; Want = 'SysUtils, / Classes;'
     Must = @('(?m)^uses\r?\n\s+SysUtils,\r?\n\s+Classes;\r?$', '(?m)^uses\r?\n\s+Math,\r?\n\s+Types;\r?$') }
  @{ Id = 'UsesCommaLast OFF: comma-last input becomes comma-first'; Fix = 'polarity_uses'; Set = @{ UsesCommaLast = $F }
     In = 'uses<NL>Math,<NL>Types;'; Want = 'Math / , Types / ;'
     Must = @('(?m)^uses\r?\n\s+Math\r?\n\s*, Types\r?\n\s*;\r?$')
     Not = @('(?m)^\s*Math,\s*$') }

  # Delphi10Compat (default false): ON hoists inline vars into a var block;
  # OFF leaves them inline.
  @{ Id = 'Delphi10Compat ON: inline var hoisted'; Fix = 'polarity_d10'; Set = @{ Delphi10Compat = $T }
     In = 'var DcA: Integer:= 3;  (inline)'; Want = 'DcA: Integer; in a var block + DcA:= 3;'
     Must = @('(?m)^\s*DcA: Integer;\r?$', '(?m)^\s*DcA:= 3;\r?$')
     Not = @('(?m)^\s*var DcA') }
  @{ Id = 'Delphi10Compat OFF: inline var kept inline'; Fix = 'polarity_d10'; Set = @{ Delphi10Compat = $F }
     In = 'var DcA: Integer:= 3;  (inline)'; Want = 'unchanged'
     Must = @('(?m)^\s*var DcA: Integer:= 3;\r?$') }

  # Interactions with no defined precedence in the spec: only exit 0,
  # idempotence and compilability are asserted (see QUESTION list).
  @{ Id = 'PackShortBodies + BreakIfBody + BreakLoopBody all ON (bodies fixture)'; Fix = 'polarity_breakbody'; Set = @{ PackShortBodies = $T; BreakIfBody = $T; BreakLoopBody = $T } }
  @{ Id = 'PackShortBodies + BreakIfBody + BreakLoopBody all ON (pack fixture)'; Fix = 'polarity_pack'; Set = @{ PackShortBodies = $T; BreakIfBody = $T; BreakLoopBody = $T } }
)

$questions = @(
  'PackShortBodies OFF + a body already on the header line ("for I:= 0 to N do Inc(PkD);"): the spec says "every body/arm stays on its own line" -- does OFF actively break it, or only not pack? Observed: kept inline.'
  'PackShortBodies ON + BreakIfBody/BreakLoopBody ON: no precedence is specified. Observed: Break* wins for if/loop bodies; case arms are packed.'
  'PackShortBodies ON also packs a "with R do" body (observed with the bodies fixture) -- the spec only names loop/if bodies and case arms.'
  'BreakCaseLabels OFF + a multi-label arm hand-broken across lines ("7,<NL>8: X;"): "kept on one line" -- re-joined or preserved? Not asserted.'
)

# --- run --------------------------------------------------------------------
$outputs = @{}   # run key -> formatted text ($null = the run itself failed)
function Get-RunOutput($c) {
  $keys = @($c.Set.Keys | Sort-Object)
  $runKey = $c.Fix + '|' + (($keys | ForEach-Object { "$_=$($c.Set[$_])" }) -join ';')
  if ($outputs.ContainsKey($runKey)) { return $outputs[$runKey] }
  $runDir = Join-Path $work ([guid]::NewGuid().ToString('N'))
  [IO.Directory]::CreateDirectory($runDir) | Out-Null
  $ini = Join-Path $runDir 'polarity.ini'
  $body = "[Format]`r`n" + (($keys | ForEach-Object { "$_=$($c.Set[$_])`r`n" }) -join '')
  [IO.File]::WriteAllText($ini, $body, [Text.Encoding]::ASCII)
  $src  = Join-Path $fixDir ($c.Fix + '.pas')
  $out1 = Join-Path $runDir ($c.Fix + '.pas')      # keep the unit name: dcc64 E1038
  $out2 = Join-Path $runDir ($c.Fix + '.2.pas')
  $text = $null
  if ((Invoke-Yadf $src $ini $out1) -and (Invoke-Yadf $out1 $ini $out2)) {
    if (-not (SameBytes $out1 $out2)) { Fail "not idempotent: $runKey" }
    if ($haveDcc -and -not (Test-DccCompiles $out1 $fixDir $dcuDir)) { Fail "output does not compile: $runKey" }
    $text = [IO.File]::ReadAllText($out1)
  }
  $outputs[$runKey] = $text
  return $text
}

# The fixtures themselves must stay compilable (they are the spec's inputs).
if ($haveDcc) {
  Get-ChildItem $fixDir -Filter *.pas | ForEach-Object {
    if (-not (Test-UnitNameMatchesFile $_.FullName)) { return }
    if (-not (Test-DccCompiles $_.FullName $fixDir $dcuDir)) { Fail "fixture does not compile: $($_.Name)" }
  }
}
else { Fail "dcc64 missing at $(Get-Dcc64): outputs cannot be compile-checked" }

$gaps = @()
$passed = 0
try {
  foreach ($c in $cases) {
    $o = Get-RunOutput $c
    if ($null -eq $o) { continue }   # the run failure is already counted
    $bad = @()
    foreach ($rx in @($c.Must)) { if ($rx -and $o -notmatch $rx) { $bad += "missing /$rx/" } }
    foreach ($rx in @($c.Not))  { if ($rx -and $o -match $rx)    { $bad += "unexpected /$rx/" } }
    if ($c.Gap) {
      if ($bad.Count -eq 0) { Fail "KNOWN-GAP now PASSES -- remove its Gap note: $($c.Id)"; continue }
      $actual = @(($o -split "`r?`n") | Where-Object { $_ -match $c.Show -and $_ -notmatch '^\s*//' } | ForEach-Object { $_.Trim() }) -join ' | '
      $gaps += [pscustomobject]@{ Id = $c.Id; In = $c.In; Want = $c.Want; Actual = $actual; Note = $c.Gap }
      continue
    }
    if ($bad.Count -gt 0) { Fail "$($c.Id): $($bad -join '; ')"; continue }
    $passed++
  }
}
finally { [IO.Directory]::Delete($work, $true) }

Write-Output ''
Write-Output ("KNOWN-GAP list ({0}) -- YADF does not meet the spec; each is asserted and must flip when fixed:" -f $gaps.Count)
foreach ($g in $gaps) {
  Write-Output "  KNOWN-GAP [$($g.Id)]"
  Write-Output "    input   : $($g.In)"
  Write-Output "    expected: $($g.Want)"
  Write-Output "    actual  : $($g.Actual)"
  Write-Output "    severity: $($g.Note)"
}
Write-Output ("QUESTION list ({0}) -- spec ambiguous, direction not asserted:" -f $questions.Count)
foreach ($q in $questions) { Write-Output "  QUESTION: $q" }
Write-Output ''

if ($script:fail -eq 0) {
  Write-Output ("option_polarity: PASS ({0} cases passed, {1} known gaps, {2} questions)" -f $passed, $gaps.Count, $questions.Count)
  exit 0
}
Write-Output ("option_polarity: {0} FAILED ({1} passed, {2} known gaps)" -f $script:fail, $passed, $gaps.Count)
exit 1
