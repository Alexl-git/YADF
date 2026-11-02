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
  # SPEC task 2c: a trailing blank after an opening paren must not survive the join.
  @{ Id = 'ReflowLines ON: a hand break after "(" with a trailing blank joins without a stray space'; Fix = 'polarity_reflow'; Set = @{ ReflowLines = $T }
     In = 'Epsilon:= Sum3( <NL>1, 2, 3);'; Want = 'Epsilon:= Sum3(1, 2, 3);'
     Must = @('(?m)^\s*Epsilon:= Sum3\(1, 2, 3\);\r?$')
     Not = @('Sum3\( ') }
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

  # PackShortBodies is RETIRED (owner decision Q1, SPEC-2026-11-01 task 2d-1): no
  # longer an option, but PackShortBodies=true in an INI is a load-time alias for
  # BreakIfBody/BreakLoopBody/BreakWithBody = false + CaseArmOnLabelLine = true.
  @{ Id = 'PackShortBodies=true alias: for body packed'; Fix = 'polarity_pack'; Set = @{ PackShortBodies = $T }
     In = 'for I:= 0 to N do<NL>Inc(PkA);'; Want = 'one line'
     Must = @('(?m)^\s*for I:= 0 to N do Inc\(PkA\);\r?$') }
  @{ Id = 'PackShortBodies=true alias: if body packed'; Fix = 'polarity_pack'; Set = @{ PackShortBodies = $T }
     In = 'if PkA > 0 then<NL>Dec(PkB);'; Want = 'one line'
     Must = @('(?m)^\s*if PkA > 0 then Dec\(PkB\);\r?$') }
  @{ Id = 'PackShortBodies=true alias: case arm packed'; Fix = 'polarity_pack'; Set = @{ PackShortBodies = $T }
     In = '0:<NL>Inc(PkC);'; Want = '0: Inc(PkC);'
     Must = @('(?m)^\s*0: Inc\(PkC\);\r?$') }
  @{ Id = 'PackShortBodies=true alias: with body packed too (Q3)'; Fix = 'polarity_breakbody'; Set = @{ PackShortBodies = $T }
     In = 'with R do<NL>WtB:= IfB;'; Want = 'with R do WtB:= IfB;'
     Must = @('(?m)^\s*with R do WtB:= IfB;\r?$') }
  # PackShortBodies=false changes nothing: the Break*Body defaults (ON) and
  # CaseArmOnLabelLine decide.
  @{ Id = 'PackShortBodies=false alias: bodies on their own line stay there'; Fix = 'polarity_pack'; Set = @{ PackShortBodies = $F; CaseArmOnLabelLine = $F }
     In = 'for/if/case-arm with the body on its own line'; Want = 'unchanged'
     Must = @('(?m)^\s*for I:= 0 to N do\r?\n\s+Inc\(PkA\);\r?$', '(?m)^\s*if PkA > 0 then\r?\n\s+Dec\(PkB\);\r?$', '(?m)^\s*0:\r?\n\s+Inc\(PkC\);\r?$') }
  @{ Id = 'PackShortBodies=false alias: Break*Body defaults (ON) put one-line bodies on their own line'; Fix = 'polarity_pack'; Set = @{ PackShortBodies = $F }
     In = 'for I:= 0 to N do Inc(PkD); / if PkD > 0 then Dec(PkE);'; Want = 'bodies on their own line'
     Must = @('(?m)^\s*for I:= 0 to N do\r?\n\s+Inc\(PkD\);\r?$', '(?m)^\s*if PkD > 0 then\r?\n\s+Dec\(PkE\);\r?$') }

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
  @{ Id = 'CollapseShortBlocks ON + block too long for MaxLen stays expanded (begin per BeginOnHeaderLine, default OFF)'; Fix = 'polarity_collapse'; Set = @{ CollapseShortBlocks = $T }
     In = '3-statement block, ~225 chars folded'; Want = 'expanded, begin on its own line'
     Must = @('(?m)^\s*if C then\r?\n\s*begin\r?\n\s+LongNameNumberOne\s*:=')
     Not = @('begin LongNameNumberOne', '(?m)^[^\r\n]{181,}') }
  @{ Id = 'CollapseShortBlocks OFF: one-line block expands'; Fix = 'polarity_collapse'; Set = @{ CollapseShortBlocks = $F; BeginOnHeaderLine = $T }
     In = 'while CbC > 0 do begin Dec(CbC); CbD:= CbC; end;'; Want = 'one statement per line'
     Must = @('(?m)^\s*while CbC > 0 do begin\r?\n\s+Dec\(CbC\);\r?\n\s+CbD:= CbC;\r?\n\s*end;\r?$') }
  @{ Id = 'CollapseShortBlocks OFF: expanded block stays expanded'; Fix = 'polarity_collapse'; Set = @{ CollapseShortBlocks = $F; BeginOnHeaderLine = $T }
     In = 'if C then begin<NL>CbA:= 1;<NL>CbB:= 2;<NL>end;'; Want = 'unchanged'
     Must = @('(?m)^\s*if C then begin\r?\n\s+CbA:= 1;\r?\n\s+CbB:= 2;\r?\n\s*end;\r?$', '(?m)^\s*if not C then begin\r?\n\s+CbE:= 1;\r?\n\s+CbF:= 2;\r?\n\s*end;\r?$') }

  # BeginOnHeaderLine (default false, owner decision Q3, SPEC-2026-11-01 task 2d-2):
  # OFF = `begin` on its own line under then / do / else / a case label / the case
  # else, and `end` / `else` / `begin` on three lines; ON = `then begin`,
  # `end else begin`, `9: begin`. A `//` comment after the header pins it. Not
  # applied to a block CollapseShortBlocks folds onto one line. Q5: Collapse owns
  # `label: begin..end` and the case `else begin..end` in both directions.
  @{ Id = 'BeginOnHeaderLine OFF: begin goes on its own line after then / do'; Fix = 'polarity_begin'; Set = @{ BeginOnHeaderLine = $F }
     In = 'if C then begin / while BgE > 0 do begin'; Want = 'if C then / begin'
     Must = @('(?m)^(?<i> *)if C then\r?\n\k<i>begin\r?\n\k<i>  BgA:= 1;\r?$', '(?m)^(?<i> *)while BgE > 0 do\r?\n\k<i>begin\r?\n\k<i>  Dec\(BgE\);\r?$', '(?m)^(?<i> *)for BgF:= 0 to N do\r?\n\k<i>begin\r?$')
     Not = @('(?m)^[^/\r\n]*\b(then|do|else)[ ]+begin') }
  @{ Id = 'BeginOnHeaderLine OFF: end else begin goes on three lines'; Fix = 'polarity_begin'; Set = @{ BeginOnHeaderLine = $F }
     In = 'end else begin'; Want = 'end / else / begin'
     Must = @('(?m)^(?<i> *)  BgD:= 2;\r?\n\k<i>end\r?\n\k<i>else\r?\n\k<i>begin\r?\n\k<i>  BgC:= 3;\r?$', '(?m)^(?<i> *)  BgC:= 2;\r?\n\k<i>end\r?\n\k<i>else\r?\n\k<i>begin\r?\n\k<i>  BgD:= 3;\r?$')
     Not = @('(?m)^[^/\r\n]*\bend[ ]+else') }
  @{ Id = 'BeginOnHeaderLine OFF: a // comment after begin moves with it, a // after then pins'; Fix = 'polarity_begin'; Set = @{ BeginOnHeaderLine = $F }
     In = 'if C then begin // note G / if not C then // note H<NL>begin'; Want = 'if C then / begin // note G'
     Must = @('(?m)^(?<i> *)if C then\r?\n\k<i>begin // note G\r?$', '(?m)^(?<i> *)if not C then // note H\r?\n\k<i>begin\r?$') }
  @{ Id = 'BeginOnHeaderLine OFF: case arm and case else begin on their own line (Q5)'; Fix = 'polarity_begin'; Set = @{ BeginOnHeaderLine = $F }
     In = '9: begin / 10: begin X; Y; end; / 11:<NL>begin / else begin'; Want = 'label / begin / body / end at the begin column'
     Must = @('(?m)^(?<i> *)9:\r?\n\k<i>begin\r?\n\k<i>  BgA:= 9;\r?\n\k<i>  BgB:= 9;\r?\n\k<i>end;\r?$', '(?m)^(?<i> *)10:\r?\n\k<i>begin\r?\n\k<i>  BgA:= 10;\r?\n\k<i>  BgB:= 10;\r?\n\k<i>end;\r?$',
              '(?m)^(?<i> *)11:\r?\n\k<i>begin\r?\n\k<i>  BgA:= 11;\r?$', '(?m)^(?<i> *)else\r?\n\k<i>begin\r?\n\k<i>  BgA:= 0;\r?$')
     Not = @('(?m)^\s*\d+:[ ]*begin') }
  @{ Id = 'BeginOnHeaderLine ON: begin joins its then / do header'; Fix = 'polarity_begin'; Set = @{ BeginOnHeaderLine = $T }
     In = 'if not C then<NL>begin / for .. do<NL>begin'; Want = 'if not C then begin'
     Must = @('(?m)^(?<i> *)if not C then begin\r?\n\k<i>  BgB:= 1;\r?$', '(?m)^(?<i> *)for BgF:= 0 to N do begin\r?\n\k<i>  BgE:= BgF;\r?$', '(?m)^\s*if C then begin\r?\n\s+BgA:= 1;\r?$', '(?m)^\s*while BgE > 0 do begin\r?$')
     }
  @{ Id = 'BeginOnHeaderLine ON: end / else / begin joined to end else begin'; Fix = 'polarity_begin'; Set = @{ BeginOnHeaderLine = $T }
     In = 'end<NL>else<NL>begin'; Want = 'end else begin'
     Must = @('(?m)^(?<i> *)  BgC:= 2;\r?\n\k<i>end else begin\r?\n\k<i>  BgD:= 3;\r?$', '(?m)^(?<i> *)  BgD:= 2;\r?\n\k<i>end else begin\r?$') }
  @{ Id = 'BeginOnHeaderLine ON: a // comment after then keeps begin on its own line'; Fix = 'polarity_begin'; Set = @{ BeginOnHeaderLine = $T }
     In = 'if not C then // note H<NL>begin'; Want = 'unchanged'
     Must = @('(?m)^(?<i> *)if not C then // note H\r?\n\k<i>begin\r?$', '(?m)^\s*if C then begin // note G\r?$') }
  @{ Id = 'BeginOnHeaderLine ON: case arm and case else begin on the label line (Q5)'; Fix = 'polarity_begin'; Set = @{ BeginOnHeaderLine = $T }
     In = '11:<NL>begin / else<NL>begin / 10: begin X; Y; end;'; Want = '11: begin / else begin / 10 expanded'
     Must = @('(?m)^(?<i> *)9: begin\r?\n\k<i>  BgA:= 9;\r?\n\k<i>  BgB:= 9;\r?\n\k<i>end;\r?$', '(?m)^(?<i> *)10: begin\r?\n\k<i>  BgA:= 10;\r?\n\k<i>  BgB:= 10;\r?\n\k<i>end;\r?$',
              '(?m)^(?<i> *)11: begin\r?\n\k<i>  BgA:= 11;\r?$', '(?m)^(?<i> *)else begin\r?\n\k<i>  BgA:= 0;\r?$') }
  @{ Id = 'BeginOnHeaderLine OFF + CollapseShortBlocks ON: short blocks fold anyway (Collapse wins)'; Fix = 'polarity_begin'; Set = @{ BeginOnHeaderLine = $F; CollapseShortBlocks = $T }
     In = 'then begin / then<NL>begin / end else begin / arms / case else'; Want = 'one-line blocks'
     Must = @('(?m)^\s*if C then begin BgA:= 1; BgB:= 2; end;\r?$', '(?m)^\s*if not C then begin BgB:= 1; BgC:= 2; end;\r?$', '(?m)^\s*if BgA > 0 then begin BgC:= 1; BgD:= 2; end\r?\n\s*else begin BgC:= 3; BgD:= 4; end;\r?$',
              '(?m)^\s*9\s*: begin BgA:= 9; BgB:= 9; end;\r?$', '(?m)^\s*10: begin BgA:= 10; BgB:= 10; end;\r?$', '(?m)^\s*11\s*: begin BgA:= 11; BgB:= 11; end;\r?$', '(?m)^\s*else begin BgA:= 0; BgB:= 0; end;\r?$') }
  @{ Id = 'BeginOnHeaderLine ON + CollapseShortBlocks ON: short blocks fold, arms and case else too (Q5)'; Fix = 'polarity_begin'; Set = @{ BeginOnHeaderLine = $T; CollapseShortBlocks = $T }
     In = 'blocks + arms + case else'; Want = 'one-line blocks'
     Must = @('(?m)^\s*if not C then begin BgB:= 1; BgC:= 2; end;\r?$', '(?m)^\s*while BgE > 0 do begin Dec\(BgE\); BgF:= BgE; end;\r?$', '(?m)^\s*9\s*: begin BgA:= 9; BgB:= 9; end;\r?$', '(?m)^\s*11\s*: begin BgA:= 11; BgB:= 11; end;\r?$', '(?m)^\s*else begin BgA:= 0; BgB:= 0; end;\r?$') }
  @{ Id = 'BeginOnHeaderLine ON + CaseArmOnLabelLine OFF: block arms keep begin on the label line'; Fix = 'polarity_begin'; Set = @{ BeginOnHeaderLine = $T; CaseArmOnLabelLine = $F }
     In = '9: begin / 11:<NL>begin'; Want = '9: begin / 11: begin'
     Must = @('(?m)^\s*9: begin\r?$', '(?m)^\s*11: begin\r?$', '(?m)^\s*else begin\r?$') }
  @{ Id = 'BeginOnHeaderLine OFF + CaseArmOnLabelLine ON: block arms get begin on its own line'; Fix = 'polarity_begin'; Set = @{ BeginOnHeaderLine = $F; CaseArmOnLabelLine = $T }
     In = '9: begin'; Want = '9: / begin'
     Must = @('(?m)^(?<i> *)9:\r?\n\k<i>begin\r?$', '(?m)^(?<i> *)11:\r?\n\k<i>begin\r?$') }
  @{ Id = 'BeginOnHeaderLine ON + ReflowLines OFF: begin still joins its header'; Fix = 'polarity_begin'; Set = @{ BeginOnHeaderLine = $T; ReflowLines = $F }
     In = 'if not C then<NL>begin'; Want = 'if not C then begin'
     Must = @('(?m)^\s*if not C then begin\r?$', '(?m)^\s*end else begin\r?$', '(?m)^\s*11: begin\r?$') }
  @{ Id = 'BeginOnHeaderLine OFF + ReflowLines OFF: begin still split from its header'; Fix = 'polarity_begin'; Set = @{ BeginOnHeaderLine = $F; ReflowLines = $F }
     In = 'if C then begin'; Want = 'if C then / begin'
     Must = @('(?m)^(?<i> *)if C then\r?\n\k<i>begin\r?$', '(?m)^(?<i> *)9:\r?\n\k<i>begin\r?$')
     Not = @('(?m)^[^/\r\n]*\b(then|do|else)[ ]+begin', '(?m)^[^/\r\n]*\bend[ ]+else') }

  # BreakIfBody / BreakLoopBody / BreakWithBody (default TRUE since task 2d-1,
  # owner decision Q1): two-way. ON = every simple body on its own line; OFF =
  # the body is joined onto its header when it fits MaxLen. An if/else is all or
  # nothing (Q9): one line when it fits, else every body on its own line. A body
  # is never packed onto a header that spans several lines (Q10); a brace comment
  # after then stays on the header line (Q18); the case else part belongs to
  # CaseArmOnLabelLine (Q11).
  @{ Id = 'BreakIfBody ON: then/else bodies broken'; Fix = 'polarity_breakbody'; Set = @{ BreakIfBody = $T }
     In = 'if C then IfA:= 1 else IfA:= 2; / if C then IfE:= 1<NL>else IfE:= 2;'; Want = '4-line form'
     Must = @('(?m)^\s*if C then\r?\n\s+IfA:= 1\r?\n\s*else\r?\n\s+IfA:= 2;\r?$', '(?m)^\s*if C then\r?\n\s+IfE:= 1\r?\n\s*else\r?\n\s+IfE:= 2;\r?$') }
  @{ Id = 'BreakIfBody ON: a brace comment after then stays on the header line (Q18)'; Fix = 'polarity_breakbody'; Set = @{ BreakIfBody = $T }
     In = 'if C then { why } IfD:= 1;'; Want = 'if C then { why } / IfD:= 1;'
     Must = @('(?m)^\s*if C then \{ why \}\r?\n\s+IfD:= 1;\r?$') }
  @{ Id = 'BreakIfBody OFF: one-line if kept, 4-line and half-broken if joined (Q1, Q9)'; Fix = 'polarity_breakbody'; Set = @{ BreakIfBody = $F }
     In = 'IfA one line, IfB 4 lines, IfE broken before else'; Want = 'all on one line'
     Must = @('(?m)^\s*if C then IfA:= 1 else IfA:= 2;\r?$', '(?m)^\s*if C then IfB:= 1 else IfB:= 2;\r?$', '(?m)^\s*if C then IfE:= 1 else IfE:= 2;\r?$', '(?m)^\s*if C then \{ why \} IfD:= 1;\r?$') }
  @{ Id = 'BreakIfBody OFF + MaxLen 80: an if/else that does not fit gets the 4-line form (Q9)'; Fix = 'polarity_breakbody'; Set = @{ BreakIfBody = $F; MaxLen = 80 }
     In = 'if C then IfF:= ...<NL>else IfF:= ...; (97 chars joined)'; Want = 'if C then / IfF:= ... / else / IfF:= ...;'
     Must = @('(?m)^\s*if C then\r?\n\s+IfF:= IfA \+ IfB \+ LpA \+ LpB \+ LpC \+ LpD\r?\n\s*else\r?\n\s+IfF:= IfA - IfB - LpA - LpB - LpC - LpD;\r?$') }
  # MaxLen 40: the header does not fit joined, so it keeps spanning two lines (Q6).
  @{ Id = 'BreakIfBody OFF + MaxLen 40: a body is never packed onto a header spanning several lines (Q10)'; Fix = 'polarity_breakbody'; Set = @{ BreakIfBody = $F; MaxLen = '40' }
     In = 'if (LpA > 0)<NL>and (LpB > 0) and (LpC > 0) then<NL>Inc(LpA);'; Want = 'body stays on its own line'
     Must = @('(?m)^\s*and \(LpB > 0\) and \(LpC > 0\) then\r?\n\s+Inc\(LpA\);\r?$') }
  @{ Id = 'BreakIfBody OFF: a hand-broken header that fits is joined (Q6), then its body joins it'; Fix = 'polarity_breakbody'; Set = @{ BreakIfBody = $F }
     In = 'if (LpA > 0)<NL>and (LpB > 0) and (LpC > 0) then<NL>Inc(LpA);'; Want = 'one line'
     Must = @('(?m)^\s*if \(LpA > 0\) and \(LpB > 0\) and \(LpC > 0\) then Inc\(LpA\);\r?$') }
  @{ Id = 'BreakIfBody OFF + ReflowLines OFF: still joined'; Fix = 'polarity_breakbody'; Set = @{ BreakIfBody = $F; ReflowLines = $F }
     In = 'IfB 4 lines'; Want = 'one line'
     Must = @('(?m)^\s*if C then IfB:= 1 else IfB:= 2;\r?$') }

  @{ Id = 'BreakLoopBody ON: while/for bodies broken, commented body left alone'; Fix = 'polarity_breakbody'; Set = @{ BreakLoopBody = $T }
     In = 'while LpA > 0 do Dec(LpA); / for ... do Inc(LpB);'; Want = 'body on its own line'
     Must = @('(?m)^\s*while LpA > 0 do\r?\n\s+Dec\(LpA\);\r?$', '(?m)^\s*for I:= 0 to 3 do\r?\n\s+Inc\(LpB\);\r?$', '(?m)^\s*while LpE > 0 do Dec\(LpE\); // keep\r?$') }
  @{ Id = 'BreakLoopBody OFF: inline kept inline, broken joined (Q1)'; Fix = 'polarity_breakbody'; Set = @{ BreakLoopBody = $F }
     In = 'LpA/LpB inline, LpC/LpD broken'; Want = 'all on one line'
     Must = @('(?m)^\s*while LpA > 0 do Dec\(LpA\);\r?$', '(?m)^\s*for I:= 0 to 3 do Inc\(LpB\);\r?$', '(?m)^\s*while LpC > 0 do Dec\(LpC\);\r?$', '(?m)^\s*for I:= 0 to 3 do Inc\(LpD\);\r?$', '(?m)^\s*while LpE > 0 do Dec\(LpE\); // keep\r?$') }
  @{ Id = 'BreakLoopBody OFF + ReflowLines OFF: still joined'; Fix = 'polarity_breakbody'; Set = @{ BreakLoopBody = $F; ReflowLines = $F }
     In = 'LpC broken'; Want = 'one line'
     Must = @('(?m)^\s*while LpC > 0 do Dec\(LpC\);\r?$') }

  @{ Id = 'BreakWithBody ON: with body broken'; Fix = 'polarity_breakbody'; Set = @{ BreakWithBody = $T }
     In = 'with R do WtA:= IfA;'; Want = 'body on its own line'
     Must = @('(?m)^\s*with R do\r?\n\s+WtA:= IfA;\r?$') }
  @{ Id = 'BreakWithBody OFF: inline kept inline, broken joined (Q1)'; Fix = 'polarity_breakbody'; Set = @{ BreakWithBody = $F }
     In = 'WtA inline, WtB broken'; Want = 'both on one line'
     Must = @('(?m)^\s*with R do WtA:= IfA;\r?$', '(?m)^\s*with R do WtB:= IfB;\r?$') }

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

  # JoinRoutineHeaders (default true, owner decision 2026-11-01): ON = a routine
  # header the author split is joined (wrapped at MaxLen); OFF is COUPLED to
  # BreakParamsOnePerLine: OFF implies one parameter per line (2+ parameters).
  @{ Id = 'JoinRoutineHeaders ON: split header joined, long header wrapped at MaxLen'; Fix = 'polarity_joinhdr'; Set = @{ JoinRoutineHeaders = $T; MaxLen = 80 }
     In = 'procedure JhSplit(<NL>const PA: string;<NL>PB: Integer); / JhLong broken once (105 chars joined)'; Want = 'JhSplit on one line, JhLong re-wrapped, no line > 80'
     Must = @('(?m)^procedure JhSplit\(const PA: string; PB: Integer\);\r?$', '(?m)^procedure JhOne\(const PA: string\);\r?$',
              '(?m)^procedure JhLong\(const PrefixOne: string; PrefixTwo: Integer;\r?\n\s+const PrefixThree: string; PrefixFour: Boolean\);\r?$')
     Not = @('(?m)^[^\r\n]{81,}', '(?m)^\s*const PA: string;?\s*$') }
  @{ Id = 'JoinRoutineHeaders OFF: one parameter per line (implies BreakParamsOnePerLine)'; Fix = 'polarity_joinhdr'; Set = @{ JoinRoutineHeaders = $F; BreakParamsOnePerLine = $F }
     In = 'JhSplit/JhLong split, BreakParamsOnePerLine = false'; Want = 'one parameter per line'
     Must = @('(?m)^\s*const PA: string\r?$', '(?m)^\s*;?\s*PB: Integer\r?$', '(?m)^\s*const PrefixOne: string\r?$', '(?m)^\s*;?\s*PrefixFour: Boolean\r?$', '(?m)^procedure JhOne\(const PA: string\);\r?$')
     Not = @('(?m)^[^\r\n]*PA: string[^\r\n]*PB: Integer', '(?m)^[^\r\n]*PrefixOne: string[^\r\n]*PrefixTwo') }
  @{ Id = 'JoinRoutineHeaders OFF + BreakParamsOnePerLine ON: same one-per-line layout'; Fix = 'polarity_joinhdr'; Set = @{ JoinRoutineHeaders = $F; BreakParamsOnePerLine = $T }
     In = 'JhSplit/JhLong split'; Want = 'one parameter per line'
     Must = @('(?m)^\s*const PA: string\r?$', '(?m)^\s*;?\s*PB: Integer\r?$', '(?m)^\s*;?\s*PrefixTwo: Integer\r?$') }
  @{ Id = 'JoinRoutineHeaders ON + BreakParamsOnePerLine ON: BreakParams alone still works'; Fix = 'polarity_joinhdr'; Set = @{ JoinRoutineHeaders = $T; BreakParamsOnePerLine = $T }
     In = 'JhSplit split'; Want = 'one parameter per line'
     Must = @('(?m)^\s*const PA: string\r?$', '(?m)^\s*;?\s*PB: Integer\r?$') }

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
  # Q6 (SPEC-2026-11-01 task 2d-4a): an operator-leading hand break is joined when
  # the whole statement fits MaxLen; the one-per-line guard only protects
  # statements longer than MaxLen (the W case above stays one per line).
  @{ Id = 'BreakLongExpressions ON: operator-leading hand breaks join when the statement fits (Q6)'; Fix = 'polarity_lists'; Set = @{ BreakLongExpressions = $T }
     In = 'J:= I / + 1;  and  if (I > 0) / and (J > 0) then'; Want = 'one line each'
     Must = @('(?m)^\s*J:= I \+ 1;\r?$', '(?m)^\s*if \(I > 0\) and \(J > 0\) then\r?$') }
  # Q6 extension: a bracketed list longer than MaxLen is a tree -- comma-first,
  # one whole top-level branch per line, a branch that does not fit is broken the
  # same way one level down; "(" ends the header line, ")" gets its own line; a
  # list that fits is joined (no " ," left from comma-first input).
  @{ Id = 'BreakLongExpressions ON: a comma-first constant that fits is joined (Q6 ext)'; Fix = 'polarity_lists'; Set = @{ BreakLongExpressions = $T }
     In = 'Pts = ( / (X: 1; Y: 2) / , (X: 3; Y: 4) / , (X: 5; Y: 6) / );'; Want = 'one line'
     Must = @('(?m)^\s*Pts\s*: array\[0\.\.2\] of TPt\s*= \(\(X: 1; Y: 2\), \(X: 3; Y: 4\), \(X: 5; Y: 6\)\);\r?$') }
  @{ Id = 'BreakLongExpressions ON: a long array of records -- one whole record per line, comma-first (Q6 ext)'; Fix = 'polarity_lists'; Set = @{ BreakLongExpressions = $T }
     In = 'Recs = ((X: ..; Y: ..), ... 10 records) on one line > 180'; Want = 'comma-first, one record per line, ); alone'
     Must = @('(?m)^  Recs\s*: array\[0\.\.9\] of TPt\s*= \(\r?\n    \(X: 1000001; Y: 2000002\)\r?\n  , \(X: 3000003; Y: 4000004\)\r?$',
              '(?m)^  , \(X: 1900019; Y: 2000020\)\r?\n  \);\r?$')
     Not = @('(?m)\(X: \d{7}; Y: \d{7}\),', '(?m)^\s+\(?X: \d+;\r?$') }
  @{ Id = 'BreakLongExpressions ON: a branch that does not fit is broken one level down (Q6 ext)'; Fix = 'polarity_lists'; Set = @{ BreakLongExpressions = $T }
     In = 'Grid = ((24 numbers), (24 numbers)), each row > 180'; Want = 'rows broken comma-first inside, rows comma-first outside'
     Must = @('(?m)^  Grid\s*: array\[0\.\.1, 0\.\.23\] of Integer\s*= \(\r?\n    \(\r?\n      100001\r?\n    , 100002\r?$',
              '(?m)^    , 100024\r?\n    \)\r?\n  , \(\r?\n      200001\r?$', '(?m)^    , 200024\r?\n    \)\r?\n  \);\r?$') }
  @{ Id = 'BreakLongExpressions ON: a long argument list -- comma-first, one argument per line (Q6 ext)'; Fix = 'polarity_lists'; Set = @{ BreakLongExpressions = $T }
     In = 'Result:= Sum8(8 arguments) on one line > 180'; Want = 'comma-first, ); alone'
     Must = @('(?m)^  Result:= Sum8\(\r?\n    Recs\[0\]\.X \+ Recs\[1\]\.X \+ Recs\[2\]\.X\r?\n  , Recs\[3\]\.X',
              '(?m)^  , Grid\[1, 23\]\r?\n  \);\r?$') }
  # Q12 (SPEC-2026-11-01 task 2d-4b), a fixed rule under any option set: no blank
  # after "(" or before ")".
  @{ Id = 'Rule: tight parens -- no blank after "(" or before ")" (Q12)'; Fix = 'polarity_spacing'; Set = @{ ReflowLines = $T }
     In = 'Sq( SpOne ) + ( SpTwenty * 2 ); IntToStr( Alpha ); if ( Alpha > 0 ) and ( B <> '''' )'; Want = 'tight'
     Must = @('(?m)^\s*Alpha:= Sq\(SpOne\) \+ \(SpTwenty \* 2\);\r?$', '(?m)^\s*B:= IntToStr\(Alpha\);\r?$', '(?m)^\s*if \(Alpha > 0\) and \(B <> ''''\) then\r?$')
     Not = @('(?m)^(?!\s*//)[^\r\n]*\( ', '(?m)^(?!\s*//)[^\r\n]* \)') }
  @{ Id = 'Rule + ReflowLines OFF: tight parens too (Q12)'; Fix = 'polarity_spacing'; Set = @{ ReflowLines = $F }
     In = 'the same'; Want = 'tight'
     Must = @('(?m)^\s*Alpha:= Sq\(SpOne\) \+ \(SpTwenty \* 2\);\r?$')
     Not = @('(?m)^(?!\s*//)[^\r\n]*\( ', '(?m)^(?!\s*//)[^\r\n]* \)') }
  # Q13: every align option OFF -> plain "Name: Type;" / "Name = Value;", the
  # author's padding is not kept; ON (default) -> aligned columns.
  @{ Id = 'All align options OFF: plain "Name: Type;" and "Name = Value;" (Q13)'; Fix = 'polarity_spacing'; Set = @{ AlignTypeColon = $F; AlignDeclSemicolons = $F; AlignConstEquals = $F; AlignSmartAssign = $F }
     In = 'Alpha   : Integer; / B       : string ; / SpOne     = 1;'; Want = 'Alpha: Integer; / B: string; / SpOne = 1;'
     Must = @('(?m)^\s*Alpha: Integer;\r?$', '(?m)^\s*B: string;\r?$', '(?m)^\s*SpOne = 1;\r?$', '(?m)^\s*SpTwenty = 20;\r?$') }
  @{ Id = 'Align options ON (default): declaration columns aligned (Q13 ON side)'; Fix = 'polarity_spacing'; Set = @{ AlignTypeColon = $T; AlignConstEquals = $T }
     In = 'the same'; Want = 'aligned'
     Must = @('(?m)^\s*Alpha: Integer;\r?$', '(?m)^\s*B    : string', '(?m)^\s*SpOne    = 1;\r?$', '(?m)^\s*SpTwenty = 20;\r?$') }
  @{ Id = 'BreakLongExpressions OFF: long lists packed greedily comma-last, comma-first input joined (Q6 ext)'; Fix = 'polarity_lists'; Set = @{ BreakLongExpressions = $F }
     In = 'the same lists'; Want = 'several records per line, comma-last; Pts on one line'
     Must = @('(?m)^\s+\(X: 1000001; Y: 2000002\), \(X: 3000003; Y: 4000004\),',
              '(?m)^\s*Pts\s*: array\[0\.\.2\] of TPt\s*= \(\(X: 1; Y: 2\), \(X: 3; Y: 4\), \(X: 5; Y: 6\)\);\r?$')
     Not = @('(?m)^\s*, \(X', '(?m)^[^\r\n]{181,}') }

  # BreakCaseLabels (default false).
  @{ Id = 'BreakCaseLabels ON: multi-label arm split, statement duplicated'; Fix = 'polarity_caselabels'; Set = @{ BreakCaseLabels = $T }
     In = '1, 2, 3: Inc(CsA);'; Want = '1: Inc(CsA); / 2: ... / 3: ...'
     Must = @('(?m)^\s*1: Inc\(CsA\);\r?\n\s*2: Inc\(CsA\);\r?\n\s*3: Inc\(CsA\);\r?$') }
  @{ Id = 'BreakCaseLabels OFF: multi-label arm kept, single arms not merged'; Fix = 'polarity_caselabels'; Set = @{ BreakCaseLabels = $F }
     In = '1, 2, 3: Inc(CsA); 5: Inc(CsB); 6: Inc(CsB);'; Want = 'unchanged'
     Must = @('(?m)^\s*1, 2, 3: Inc\(CsA\);\r?$', '(?m)^\s*5\s*: Inc\(CsB\);\r?$', '(?m)^\s*6\s*: Inc\(CsB\);\r?$') }
  @{ Id = 'BreakCaseLabels ON: hand-broken multi-label arm split too'; Fix = 'polarity_caselabels'; Set = @{ BreakCaseLabels = $T }
     In = '7,<NL>8: Inc(CsC);'; Want = '7: Inc(CsC); / 8: Inc(CsC);'
     Must = @('(?m)^\s*7\s*: Inc\(CsC\);\r?\n\s*8\s*: Inc\(CsC\);\r?$') }
  # Owner decision Q5 (SPEC-2026-11-01): OFF always joins a multi-label arm,
  # even when hand-broken, and keeps the colon alignment with its neighbours.
  @{ Id = 'BreakCaseLabels OFF: hand-broken multi-label arm joined, colons aligned (Q5)'; Fix = 'polarity_caselabels'; Set = @{ BreakCaseLabels = $F }
     In = '7,<NL>8: Inc(CsC); / 9, 10: Inc(CsD);'; Want = '7, 8 : Inc(CsC); / 9, 10: Inc(CsD);'
     Must = @('(?m)^(?<i>[ ]*)7, 8 (?<p>[ ]*): Inc\(CsC\);\r?\n\k<i>9, 10\k<p>: Inc\(CsD\);\r?$') }
  @{ Id = 'BreakCaseLabels OFF + ReflowLines OFF: hand-broken multi-label arm still joined (Q5)'; Fix = 'polarity_caselabels'; Set = @{ BreakCaseLabels = $F; ReflowLines = $F }
     In = '7,<NL>8: Inc(CsC);'; Want = '7, 8 : Inc(CsC);'
     Must = @('(?m)^(?<i>[ ]*)7, 8 (?<p>[ ]*): Inc\(CsC\);\r?\n\k<i>9, 10\k<p>: Inc\(CsD\);\r?$') }

  # CaseArmOnLabelLine (default true, owner decision Q2): ON = a case arm whose
  # body is one short simple statement sits on the label line (joined when it
  # fits MaxLen); OFF = the statement goes on its own line under the label.
  # PackShortBodies=true (alias) implies ON. begin/case/try arms, a
  # record variant part and "name: type;" declarations are never touched.
  @{ Id = 'CaseArmOnLabelLine ON: arm under its label is joined, inline arms kept'; Fix = 'polarity_casearm'; Set = @{ CaseArmOnLabelLine = $T; BreakIfBody = $T }
     In = '0:<NL>Inc(CaA); / 1: Inc(CaB); / 3: Inc(CaD); // keep'; Want = '0: Inc(CaA); and the rest unchanged'
     Must = @('(?m)^\s*0: Inc\(CaA\);\r?$', '(?m)^\s*1: Inc\(CaB\);\r?$', '(?m)^\s*3: Inc\(CaD\); // keep\r?$', '(?m)^\s*else CaA:= 1;\r?$', '(?m)^\s*else Dec\(CaB\);\r?$', '(?m)^\s*7: Inc\(CaA, CaB\);\r?$',
              '(?m)^\s*0\s*: \(IntVal: Integer\);\r?$', '(?m)^\s*4:\r?\n\s+case CaB of\r?$', '(?m)^\s*0: Inc\(CaB\);\r?$', '(?m)^(?<i> *)5:\r?\n\k<i>  if CaA > 0 then\r?\n\k<i>    Inc\(CaA\)\r?\n\k<i>  else\r?\n\k<i>    Dec\(CaA\);\r?$',
              '(?m)^(?<i> *)8:\r?\n\k<i>  if CaA > 1 then\r?\n\k<i>    Inc\(CaB\)\r?\n\k<i>  else\r?\n\k<i>    Dec\(CaB\);\r?$')
     Not = @('(?m)^[ ]*2:[ ]*begin', '(?m)^[ ]*4:[ ]*case', '(?m)Inc\([^)
]*\)[ ]+;') }
  # Task 2d-2: an if inside an arm follows BreakIfBody exactly as elsewhere (never
  # half-split); OFF + CaseArmOnLabelLine ON puts the whole if on the label line.
  @{ Id = 'CaseArmOnLabelLine ON + BreakIfBody OFF: an arm if goes on its label line whole'; Fix = 'polarity_casearm'; Set = @{ CaseArmOnLabelLine = $T; BreakIfBody = $F }
     In = '5: if C then A else B; / 8: if C then A<NL>else B;'; Want = 'one line each'
     Must = @('(?m)^\s*5: if CaA > 0 then Inc\(CaA\) else Dec\(CaA\);\r?$', '(?m)^\s*8: if CaA > 1 then Inc\(CaB\) else Dec\(CaB\);\r?$') }
  @{ Id = 'CaseArmOnLabelLine OFF + BreakIfBody OFF: an arm if goes whole under its label'; Fix = 'polarity_casearm'; Set = @{ CaseArmOnLabelLine = $F; BreakIfBody = $F }
     In = '8: if C then A<NL>else B;'; Want = '8: / if C then A else B;'
     Must = @('(?m)^(?<i> *)8:\r?\n\k<i>  if CaA > 1 then Inc\(CaB\) else Dec\(CaB\);\r?$', '(?m)^(?<i> *)5:\r?\n\k<i>  if CaA > 0 then Inc\(CaA\) else Dec\(CaA\);\r?$') }
  # Q11 + Q16 (task 2d-1): the case else part follows CaseArmOnLabelLine, never
  # BreakIfBody; a one-line arm is never padded before its ";".
  @{ Id = 'CaseArmOnLabelLine OFF + BreakIfBody OFF: case else stays broken'; Fix = 'polarity_casearm'; Set = @{ CaseArmOnLabelLine = $F; BreakIfBody = $F }
     In = 'else<NL>CaA:= 1;'; Want = 'unchanged'
     Must = @('(?m)^\s*else\r?\n\s+CaA:= 1;\r?$', '(?m)^\s*else\r?\n\s+Dec\(CaB\);\r?$') }
  @{ Id = 'CaseArmOnLabelLine ON + ReflowLines OFF: no ";" padding on one-line arms (Q16)'; Fix = 'polarity_casearm'; Set = @{ CaseArmOnLabelLine = $T; ReflowLines = $F }
     In = '1: Inc(CaB); / 7: Inc(CaA, CaB);'; Want = 'no blanks before ";"'
     Must = @('(?m)^\s*7: Inc\(CaA, CaB\);\r?$', '(?m)^\s*1: Inc\(CaB\);\r?$')
     Not = @('(?m)Inc\([^)
]*\)[ ]+;') }
  @{ Id = 'CaseArmOnLabelLine OFF: arm statements go under their label'; Fix = 'polarity_casearm'; Set = @{ CaseArmOnLabelLine = $F }
     In = '1: Inc(CaB); / 3: Inc(CaD); // keep / 5: if ..'; Want = '1: / Inc(CaB); and 3: / Inc(CaD); // keep'
     Must = @('(?m)^\s*0:\r?\n\s+Inc\(CaA\);\r?$', '(?m)^\s*1:\r?\n\s+Inc\(CaB\);\r?$', '(?m)^\s*3:\r?\n\s+Inc\(CaD\); // keep\r?$', '(?m)^\s*else\r?\n\s+CaA:= 1;\r?$', '(?m)^\s*else\r?\n\s+Dec\(CaB\);\r?$',
              '(?m)^\s*0:\r?\n\s+Inc\(CaB\);\r?$', '(?m)^\s*5:\r?\n\s+if CaA > 0 then\r?\n\s+Inc\(CaA\)\r?\n\s*else\r?\n\s+Dec\(CaA\);\r?$', '(?m)^(?<i> *)8:\r?\n\k<i>  if CaA > 1 then\r?\n\k<i>    Inc\(CaB\)\r?\n\k<i>  else\r?\n\k<i>    Dec\(CaB\);\r?$',
              '(?m)^\s*0\s*: \(IntVal: Integer\);\r?$', '(?m)^\s*case Kind: Integer of\r?$', '(?m)^\s*CaA\s*: Integer;\r?$', '(?m)^procedure RunCaseArm\(N: Integer\);\r?$')
     Not = @('(?m)^[ ]*[0-5]:[ ]*(Inc|Dec|begin|case|if)') }
  # SPEC task 2c: moving the statement under its label shifts the continuation
  # lines by the SAME amount (they keep their offset from the statement start).
  # MaxLen 40: the arm-6 statement does not fit joined, so its operator-leading
  # break is BreakLongExpressions' layout and stays (Q6); at 180 it is joined.
  @{ Id = 'CaseArmOnLabelLine OFF + MaxLen 40: continuation lines keep their offset to the statement'; Fix = 'polarity_casearm'; Set = @{ CaseArmOnLabelLine = $F; MaxLen = '40' }
     In = '6: CaB:= CaA + CaC + CaD + CaA<NL>         + CaC + CaD;'; Want = '6: / CaB:= CaA + CaC + CaD + CaA / (statement + 2) + CaC + CaD;'
     Must = @('(?m)^(?<i> *)6:\r?\n\k<i>  CaB:= CaA \+ CaC \+ CaD \+ CaA\r?\n\k<i>    \+ CaC \+ CaD;\r?$') }
  @{ Id = 'CaseArmOnLabelLine ON + MaxLen 40: a broken statement on the label line is left as written'; Fix = 'polarity_casearm'; Set = @{ CaseArmOnLabelLine = $T; MaxLen = '40' }
     In = '6: CaB:= CaA + CaC + CaD + CaA<NL>         + CaC + CaD;'; Want = 'unchanged'
     Must = @('(?m)^(?<i> *)6: CaB:= CaA \+ CaC \+ CaD \+ CaA\r?\n\k<i>     \+ CaC \+ CaD;\r?$') }
  @{ Id = 'CaseArmOnLabelLine ON: an operator-leading hand break in an arm joins when it fits (Q6)'; Fix = 'polarity_casearm'; Set = @{ CaseArmOnLabelLine = $T }
     In = '6: CaB:= CaA + CaC + CaD + CaA<NL>         + CaC + CaD;'; Want = 'one line'
     Must = @('(?m)^\s*6: CaB:= CaA \+ CaC \+ CaD \+ CaA \+ CaC \+ CaD;\r?$') }
  @{ Id = 'CaseArmOnLabelLine OFF + PackShortBodies ON: Pack implies ON'; Fix = 'polarity_casearm'; Set = @{ CaseArmOnLabelLine = $F; PackShortBodies = $T }
     In = '0:<NL>Inc(CaA); / 1: Inc(CaB);'; Want = 'both on the label line'
     Must = @('(?m)^\s*0: Inc\(CaA\);\r?$', '(?m)^\s*1: Inc\(CaB\);\r?$') }
  @{ Id = 'CaseArmOnLabelLine ON + ReflowLines OFF: arm still joined'; Fix = 'polarity_casearm'; Set = @{ CaseArmOnLabelLine = $T; ReflowLines = $F }
     In = '0:<NL>Inc(CaA);'; Want = '0: Inc(CaA);'
     Must = @('(?m)^\s*0: Inc\(CaA\);\r?$', '(?m)^\s*1: Inc\(CaB\);\r?$') }
  @{ Id = 'CaseArmOnLabelLine OFF + ReflowLines OFF: arm still broken'; Fix = 'polarity_casearm'; Set = @{ CaseArmOnLabelLine = $F; ReflowLines = $F }
     In = '1: Inc(CaB);'; Want = '1: / Inc(CaB);'
     Must = @('(?m)^\s*0:\r?\n\s+Inc\(CaA\);\r?$', '(?m)^\s*1:\r?\n\s+Inc\(CaB\);\r?$', '(?m)^\s*0\s*: \(IntVal: Integer\);\r?$') }
  @{ Id = 'CaseArmOnLabelLine OFF + BreakCaseLabels ON: one label per arm, statement under it'; Fix = 'polarity_caselabels'; Set = @{ CaseArmOnLabelLine = $F; BreakCaseLabels = $T }
     In = '1, 2, 3: Inc(CsA);'; Want = '1: / Inc(CsA); / 2: / ...'
     Must = @('(?m)^\s*1:\r?\n\s+Inc\(CsA\);\r?\n\s*2:\r?\n\s+Inc\(CsA\);\r?\n\s*3:\r?\n\s+Inc\(CsA\);\r?$') }

  # SplitMultiVarDecls (default true).
  @{ Id = 'SplitMultiVarDecls ON: grouped decl split'; Fix = 'polarity_splitvars'; Set = @{ SplitMultiVarDecls = $T }
     In = 'SvA, SvB: Integer;'; Want = 'SvA: Integer; / SvB: Integer;'
     Must = @('(?m)^\s*SvA\s*: Integer;\r?\n\s*SvB\s*: Integer;\r?$') }
  @{ Id = 'SplitMultiVarDecls OFF: grouped decl kept, split decls unchanged'; Fix = 'polarity_splitvars'; Set = @{ SplitMultiVarDecls = $F }
     In = 'SvA, SvB: Integer; SvC/SvD separate'; Want = 'unchanged'
     Must = @('(?m)^\s*SvA, SvB\s*: Integer;\r?$', '(?m)^\s*SvC\s*: Integer;\r?\n\s*SvD\s*: Integer;\r?$', '(?m)^\s*SvE, \{note\} SvF\s*: Integer;\r?$') }
  @{ Id = 'SplitMultiVarDecls ON: a comment in the name list stays with the FIRST name'; Fix = 'polarity_splitvars'; Set = @{ SplitMultiVarDecls = $T }
     In = 'SvE, {note} SvF: Integer;'; Want = 'SvE: {note} Integer; / SvF: Integer;'
     Must = @('(?m)^\s*SvE\s*: \{note\} Integer;\r?\n\s*SvF\s*: Integer\s*;\r?$') }

  # UsesAlwaysBreak (default true) / UsesCommaLast (default false).
  @{ Id = 'UsesAlwaysBreak ON: one-line uses broken comma-first'; Fix = 'polarity_uses'; Set = @{ UsesAlwaysBreak = $T }
     In = 'uses SysUtils, Classes;'; Want = 'one unit per line, leading comma, ; alone'
     Must = @('(?m)^uses\r?\n\s+SysUtils\r?\n\s*, Classes\r?\n\s*;\r?$') }
  # G5 (SPEC-2026-11-01): the code was right, the doc was wrong -- the commas and the ; sit
  # at the unit column ("  , Classes" / "  ;"); help + yadf.ini fixed in task 4.
  @{ Id = 'UsesAlwaysBreak ON: commas and ; indented to the unit column (G5, documented shape)'; Fix = 'polarity_uses'; Set = @{ UsesAlwaysBreak = $T }
     In = 'uses SysUtils, Classes;'; Want = 'uses / "  SysUtils" / "  , Classes" / "  ;"'
     Must = @('(?m)^uses\r?\n  SysUtils\r?\n  , Classes\r?\n  ;\r?$') }
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

  # Owner decision Q2 (SPEC-2026-11-01), kept by the alias: a Break*Body set to
  # true explicitly in the same INI still wins over PackShortBodies=true.
  @{ Id = 'PackShortBodies + BreakIfBody + BreakLoopBody all ON (bodies fixture): Break wins'; Fix = 'polarity_breakbody'; Set = @{ PackShortBodies = $T; BreakIfBody = $T; BreakLoopBody = $T }
     In = 'while LpA > 0 do Dec(LpA); / if C then IfA:= 1 else IfA:= 2;'; Want = 'bodies broken'
     Must = @('(?m)^\s*while LpA > 0 do\r?\n\s+Dec\(LpA\);\r?$', '(?m)^\s*if C then\r?\n\s+IfA:= 1\r?\n\s*else\r?\n\s+IfA:= 2;\r?$') }
  @{ Id = 'PackShortBodies + BreakIfBody + BreakLoopBody all ON (pack fixture): Break wins, arms packed'; Fix = 'polarity_pack'; Set = @{ PackShortBodies = $T; BreakIfBody = $T; BreakLoopBody = $T }
     In = 'for/if bodies + case arms'; Want = 'for/if bodies broken, 0: Inc(PkC); and 1: Inc(PkF); packed'
     Must = @('(?m)^\s*for I:= 0 to N do\r?\n\s+Inc\(PkA\);\r?$', '(?m)^\s*if PkA > 0 then\r?\n\s+Dec\(PkB\);\r?$', '(?m)^\s*0: Inc\(PkC\);\r?$', '(?m)^\s*1: Inc\(PkF\);\r?$') }

  # PackStatements (SPEC-2026-11-01 task 2d-3, owner decision Q4), two-way like
  # Break*Body: OFF (default) = one statement per line, ON = adjacent plain
  # statements packed onto one line while the line fits MaxLen.
  @{ Id = 'PackStatements OFF: statements written on one line are split one per line'; Fix = 'polarity_stmts'; Set = @{ PackStatements = $F }
     In = 'StA:= 1; StB:= 2; StC:= 3;'; Want = 'three lines'; Show = 'StA:=|StB:=|StC:='
     Must = @('(?m)^\s*StA:= 1;\r?\n\s*StB:= 2;\r?\n\s*StC:= 3;\r?\n\s*StD:= 4;\r?\n\s*StE:= 5;\r?$') }
  @{ Id = 'PackStatements ON: adjacent plain statements are packed onto one line'; Fix = 'polarity_stmts'; Set = @{ PackStatements = $T }
     In = 'StA:= 1; StB:= 2; StC:= 3; / StD:= 4; / StE:= 5;'; Want = 'one line'; Show = 'StA:=|StD:=|StE:='
     Must = @('(?m)^\s*StA:= 1; StB:= 2; StC:= 3; StD:= 4; StE:= 5;\r?$', '(?m)^\s*GStA:= 1; GStB:= ''a'';\r?$') }
  @{ Id = 'PackStatements ON + MaxLen 40 (the minimum): packing stops at MaxLen'; Fix = 'polarity_stmts'; Set = @{ PackStatements = $T; MaxLen = '40' }
     In = 'five statements'; Want = 'StA..StD (37 chars) / StE'; Show = 'StA:=|StD:=|StE:='
     Must = @('(?m)^\s*StA:= 1; StB:= 2; StC:= 3; StD:= 4;\r?\n\s*StE:= 5;\r?$') }
  # Task 5b: column padding (`cfgML_STR_AXISZ     .Text   :=`, the alignment's own
  # output) is not measured -- packed exactly like the plain statements, so the
  # next format packs the same (idempotence; ORM3 uSetupDefaultsFrm).
  @{ Id = 'PackStatements ON: padded statements pack like plain ones (no blank kept before the member dot)'; Fix = 'polarity_pack_align'; Set = @{ PackStatements = $T; CollapseShortBlocks = $T; BreakIfBody = $F; BreakLoopBody = $F; CaseArmOnLabelLine = $F }
     In = 'cfgML_STR_AXISZ     .Text   := ...; (one per line, padded)'; Want = 'three per line, tight dots'; Show = 'cfgML_STR_AXISZ|cfgUseAbbrML'
     Must = @('(?m)^\s*cfgML_STR_AXISZ\.Text:= SetupDefaultsRec\.ML_STR_AXISZ; cfgML_STR_DATUM1\.Text:= SetupDefaultsRec\.ML_STR_DATUM1; cfgSetValuetoZeroUSL\.Checked:= SetupDefaultsRec\.SetValuetoZeroUSL;\r?$')
     Not = @('\w \.(Text|Checked)') }
  @{ Id = 'PackStatements ON: a block keyword is never packed (repeat / try / case lines, the if block)'; Fix = 'polarity_stmts'; Set = @{ PackStatements = $T }
     In = 'StE:= 5; / repeat ...'; Want = 'repeat starts its line'
     Must = @('(?m)^\s*repeat\r?$', '(?m)^\s*StE:= 6;\r?$')
     Not = @('StE:= 5;[ \t]*repeat', ';[ \t]*if N > 0') }
  # Fixed rule (always on): block keywords start a line, a block body never stays on
  # the header line; only CollapseShortBlocks may fold a short begin..end.
  foreach ($pk in @($F, $T)) {
    @{ Id = "Rule (PackStatements=$pk): repeat / try / case written on one line are expanded"; Fix = 'polarity_stmts'; Set = @{ PackStatements = $pk }
       In = 'repeat Dec(StA); until ...; try ... end; case N of ... end;'; Want = 'one keyword per line'; Show = 'repeat|until|try|finally|case|StD:= [12]|^\s*end;'
       Must = @('(?m)^\s*repeat\r?\n\s+Dec\(StA\);\r?\n\s*until StA <= 0;\r?$', '(?m)^\s*try\r?\n\s+StB:= N;\r?\n\s*finally\r?\n\s+StC:= 0;\r?\n\s*end;\r?$', '(?m)^\s*case N of\r?\n\s+0: StD:= 1;\r?\n\s+1: StD:= 2;\r?\n\s*end;\r?$') }
    @{ Id = "Rule (PackStatements=$pk): a one-line routine body is expanded (begin starts a line)"; Fix = 'polarity_stmts'; Set = @{ PackStatements = $pk }
       In = 'procedure OneLine; begin GStA:= 1; GStB:= ''a''; end;'; Want = 'header / begin / body / end'; Show = 'OneLine|GStA:= 1|GStB:= ''a'''
       Must = @('(?m)^procedure OneLine;\r?\nbegin\r?\n\s+GStA:= 1;' + $(if ($pk -eq $F) { '\r?\n\s+' } else { ' ' }) + 'GStB:= ''a'';\r?\nend;\r?$') }
    @{ Id = "Rule (PackStatements=$pk): a one-line record / class is expanded, one member per line (Q7)"; Fix = 'polarity_stmts'; Set = @{ PackStatements = $pk }
       In = 'TStRec = record RA: Integer; RB: Integer; end; / TStObj = class(TObject) private ...'; Want = 'one member per line'; Show = 'TStRec|TStObj|RA|RB|FX|private|public|procedure P;|^\s*end;'
       Must = @('(?m)^\s*TStRec\s*= record\r?\n\s+RA\s*: Integer;\r?\n\s+RB\s*: Integer;\r?\n\s*end;\r?$', '(?m)^\s*TStObj\s*= class\(TObject\)\r?\n\s*private\r?\n\s+FX\s*: Integer;\r?\n\s*public\r?\n\s+procedure P;\r?\n\s*end;\r?$') }
    @{ Id = "Rule (PackStatements=$pk): two var declarations on one line are split (Q7)"; Fix = 'polarity_stmts'; Set = @{ PackStatements = $pk }
       In = 'GStA: Integer; GStB: string;'; Want = 'two lines'; Show = 'GStA\s*:|GStB\s*:'
       Must = @('(?m)^\s*GStA\s*: Integer;\r?\n\s*GStB\s*: string\s*;\r?$') }
  }
  @{ Id = 'Rule + ReflowLines OFF: block keywords still start a line, statements one per line'; Fix = 'polarity_stmts'; Set = @{ ReflowLines = $F }
     In = 'repeat ... / StA:= 1; StB:= 2; StC:= 3;'; Want = 'expanded'; Show = 'repeat|StA:=|StB:='
     Must = @('(?m)^\s*repeat\r?\n\s+Dec\(StA\);\r?$', '(?m)^\s*StA:= 1;\r?\n\s*StB:= 2;\r?$') }
  @{ Id = 'Rule exception: CollapseShortBlocks ON still folds the short if block'; Fix = 'polarity_stmts'; Set = @{ CollapseShortBlocks = $T; PackStatements = $T }
     In = 'if N > 0 then / begin / StE:= 6; / end;'; Want = 'if N > 0 then begin StE:= 6; end;'; Show = 'if N > 0|StE:= 6'
     Must = @('(?m)^\s*if N > 0 then begin StE:= 6; end;\r?$', '(?m)^\s*repeat\r?$') }

  # Comment rule (SPEC-2026-11-01 task 3, a fixed rule under every option): only a
  # // line comment pins a line -- it blocks a join across it, and a split never
  # moves it off the end of its line. A short one-line {...} / (*...*) comment
  # travels with its neighbouring token: a join carries it along, a split goes
  # before the next CODE token so it stays at the end of the earlier line. A
  # multi-line block comment pins; {$...} directives never move across lines.
  @{ Id = 'Comment rule: reflow join carries a brace comment, // blocks it'; Fix = 'polarity_comments'; Set = @{ ReflowLines = $T }
     In = 'CmE:= Sum2(1, {one}<NL>2); / CmF:= Sum2(1, // one<NL>2);'; Want = 'CmE joined, CmF kept'
     Must = @('(?m)^\s*CmE:= Sum2\(1, \{one\} 2\);\r?$', '(?m)^\s*CmF:= Sum2\(1, // one\r?\n\s+2\);\r?$') }
  @{ Id = 'Comment rule: routine header join carries a brace comment, // blocks it'; Fix = 'polarity_comments'; Set = @{ JoinRoutineHeaders = $T }
     In = 'procedure CmHeadBrace(const CmA: string; { first }<NL>CmB: Integer);'; Want = 'brace header joined, // header kept'
     Must = @('(?m)^procedure CmHeadBrace\(const CmA: string; \{ first \} CmB: Integer\);\r?$', '(?m)^procedure CmHeadSlash\(const CmC: string; // first\r?\n\s+CmD: Integer\);\r?$') }
  @{ Id = 'Comment rule: Q6 operator-leading join carries a brace comment; // and a multi-line comment block it'; Fix = 'polarity_comments'; Set = @{ BreakLongExpressions = $T }
     In = 'CmG:= CmE {+ CmF}<NL>+ N; / CmH:= CmE // keep<NL>+ N;'; Want = 'CmG joined, CmH kept'; Show = 'CmG:=|CmH:=|\+ N'
     Must = @('(?m)^\s*CmG:= CmE \{\+ CmF\} \+ N;\r?$', '(?m)^\s*CmH:= CmE // keep\r?\n\s+\+ N;\r?$', '(?m)^\s*lines \}\r?\n\s+\+ N;\r?$') }
  @{ Id = 'Comment rule: comma-first list layout keeps a brace comment with its item'; Fix = 'polarity_comments'; Set = @{ BreakLongExpressions = $T }
     In = 'CmRecs = ((..), {first} (..), ...) > 180'; Want = 'comment on the item line'
     Must = @('(?m)^    \(X: 1000001; Y: 2000002\) \{first\}\r?\n  , \(X: 3000003; Y: 4000004\)\r?$') }
  @{ Id = 'Comment rule: greedy list layout (BreakLongExpressions OFF) packs across a brace comment'; Fix = 'polarity_comments'; Set = @{ BreakLongExpressions = $F }
     In = 'CmRecs = ((..), {first} (..), ...) > 180'; Want = 'comment mid-line, records packed after it'; Show = 'X: 1000001|\{first\}'
     Must = @('(?m)\(X: 1000001; Y: 2000002\), \{first\} \(X: 3000003; Y: 4000004\), ')
     Not = @('(?m)\{first\}\r?$') }
  @{ Id = 'Comment rule: BreakIfBody/BreakLoopBody OFF join a body across a brace comment, // blocks it'; Fix = 'polarity_comments'; Set = @{ BreakIfBody = $F; BreakLoopBody = $F }
     In = 'if N > 0 then {why} Inc(CmI); / if N > 1 then<NL>{short} Inc(CmI); / while .. do (*loop*)<NL>Dec(CmI);'; Want = 'one line each; the // one kept'; Show = 'if N > [012]|while CmI|Inc\(CmI\)|Dec\(CmI\)'
     Must = @('(?m)^\s*if N > 0 then \{why\} Inc\(CmI\);\r?$', '(?m)^\s*if N > 1 then \{short\} Inc\(CmI\);\r?$',
              '(?m)^\s*while CmI > 0 do \(\*loop\*\) Dec\(CmI\);\r?$', '(?m)^\s*if N > 2 then // why\r?\n\s+Inc\(CmI\);\r?$') }
  @{ Id = 'Comment rule: BreakIfBody ON splits before the body, the brace comment stays on the header line'; Fix = 'polarity_comments'; Set = @{ BreakIfBody = $T }
     In = 'if N > 0 then {why} Inc(CmI);'; Want = 'if N > 0 then {why} / Inc(CmI);'
     Must = @('(?m)^\s*if N > 0 then \{why\}\r?\n\s+Inc\(CmI\);\r?$', '(?m)^\s*if N > 1 then\r?\n\s+\{short\} Inc\(CmI\);\r?$') }
  @{ Id = 'Comment rule: CaseArmOnLabelLine ON joins an arm across a brace comment, // blocks it'; Fix = 'polarity_comments'; Set = @{ CaseArmOnLabelLine = $T }
     In = '0: {zero}<NL>Inc(CmJ); / 1:<NL>{one} Inc(CmJ); / 2: // two<NL>Inc(CmJ);'; Want = 'arms 0, 1 on the label line'; Show = '^\s*[0-7][,:]|Inc\(CmJ\)'
     Must = @('(?m)^\s*0\s*: \{zero\} Inc\(CmJ\);\r?$', '(?m)^\s*1\s*: \{one\} Inc\(CmJ\);\r?$', '(?m)^\s*2\s*: // two\r?\n\s+Inc\(CmJ\);\r?$', '(?m)^\s*3\s*: \{three\} Inc\(CmJ\);\r?$') }
  @{ Id = 'Comment rule: CaseArmOnLabelLine OFF splits before the statement, the brace comment stays on the label line'; Fix = 'polarity_comments'; Set = @{ CaseArmOnLabelLine = $F }
     In = '3: {three} Inc(CmJ);'; Want = '3: {three} / Inc(CmJ);'; Show = '^\s*[0-7][,:]|Inc\(CmJ\)'
     Must = @('(?m)^\s*3\s*: \{three\}\r?\n\s+Inc\(CmJ\);\r?$', '(?m)^\s*1\s*:\r?\n\s+\{one\} Inc\(CmJ\);\r?$', '(?m)^\s*0\s*: \{zero\}\r?\n\s+Inc\(CmJ\);\r?$') }
  @{ Id = 'Comment rule: BreakCaseLabels OFF joins a label list across a brace comment, // blocks it'; Fix = 'polarity_comments'; Set = @{ BreakCaseLabels = $F }
     In = '4, {four}<NL>5: Inc(CmJ); / 6, // six<NL>7: Inc(CmJ);'; Want = '4, {four} 5: Inc(CmJ);'; Show = '^\s*[4-7][,:]'
     Must = @('(?m)^\s*4, \{four\} 5\s*: Inc\(CmJ\);\r?$', '(?m)^\s*6, // six\r?\n\s*7\s*: Inc\(CmJ\);\r?$') }
  @{ Id = 'Comment rule: CollapseShortBlocks ON folds across brace comments; //, multi-line comments block it'; Fix = 'polarity_comments'; Set = @{ CollapseShortBlocks = $T }
     In = 'begin {blk} / begin .. (*mid*) / begin // blk / { two<NL>lines }'; Want = 'first two folded'; Show = 'if N > [3-7]|begin|CmK:=|CmL:='
     Must = @('(?m)^\s*if N > 3 then begin \{blk\} CmK:= 1; CmL:= 2; end;\r?$', '(?m)^\s*if N > 4 then begin CmK:= 3; \(\*mid\*\) CmL:= 4; end;\r?$',
              '(?m)^\s*begin // blk\r?\n\s+CmK:= 5;\r?\n\s+CmL:= 6;\r?$', '(?m)^\s*CmK:= 7; \{ two\r?\n\s*lines \}\r?\n\s+CmL:= 8;\r?$',
              '(?m)^\s*if N > 7 then begin CmK:= 9; \{nine\} CmL:= 10; end;\r?$') }
  @{ Id = 'Comment rule: CollapseShortBlocks OFF expands a one-line block holding a brace comment'; Fix = 'polarity_comments'; Set = @{ CollapseShortBlocks = $F }
     In = 'if N > 7 then begin CmK:= 9; {nine} CmL:= 10; end;'; Want = 'expanded, {nine} after CmK:= 9;'; Show = 'if N > 7|begin|CmK:= 9|CmL:= 10'
     Must = @('(?m)^\s*if N > 7 then\r?\n\s*begin\r?\n\s+CmK:= 9; \{nine\}\r?\n\s+CmL:= 10;\r?\n\s*end;\r?$', '(?m)^\s*begin \{blk\}\r?\n\s+CmK:= 1;\r?$') }
  @{ Id = 'Comment rule: PackStatements OFF splits across a brace comment, it stays on the earlier line'; Fix = 'polarity_comments'; Set = @{ PackStatements = $F }
     In = 'CmM:= 1; {a} CmN:= 2;'; Want = 'CmM:= 1; {a} / CmN:= 2;'; Show = 'CmM:=|CmN:='
     Must = @('(?m)^\s*CmM:= 1; \{a\}\r?\n\s*CmN:= 2;\r?$', '(?m)^\s*CmM:= 3; \(\*b\*\)\r?\n\s*CmN:= 4;\r?$', '(?m)^\s*\{\$IFDEF DEBUG\} CmM:= 7; \{\$ENDIF\}\r?$') }
  @{ Id = 'Comment rule: PackStatements ON packs across a brace comment; //, directives block it'; Fix = 'polarity_comments'; Set = @{ PackStatements = $T }
     In = 'CmM:= 3; (*b*)<NL>CmN:= 4; / CmM:= 5; // c<NL>CmN:= 6; / {$IFDEF}'; Want = 'packed up to the //'; Show = 'CmM:=|CmN:=|\{\$'
     Must = @('(?m)^\s*CmM:= 1; \{a\} CmN:= 2;( |\r?$)', '(?m)CmM:= 3; \(\*b\*\) CmN:= 4;', '(?m)CmM:= 5; // c\r?\n\s*CmN:= 6;\r?$',
              '(?m)^\s*\{\$IFDEF DEBUG\} CmM:= 7; \{\$ENDIF\}\r?$', '(?m)^\s*CmM:= 8;\r?\n\s*\{\$IFDEF DEBUG\}\r?\n\s*CmN:= 9;\r?\n\s*\{\$ENDIF\}\r?$') }
  # --- Task 6 (SPEC-2026-11-01 reflow-round leftovers): fixed rules at the defaults ---
  @{ Id = 'Rule: variant-record arms indent under their case, no ; padding, the case line ends the field colon run'; Fix = 'polarity_rules6'; Set = @{}
     In = 'Name: string; case Kind: Integer of 0: (...); 1: (...); 22: (...);'; Want = 'arms one level under case'; Show = 'Name|case |^\s*(0|1|22|True|False)\s*:|Count'
     Must = @('(?m)^    Name: string;\r?$', '(?m)^    case Kind: Integer of\r?$', '(?m)^      0 : \(Width, Height: Integer\);\r?$', '(?m)^      22: \(A: Byte; LongerName: Word\);\r?$',
              '(?m)^      Count: Integer;\r?$', '(?m)^    case Roomy: Boolean of\r?$', '(?m)^      True : \(Big: Int64\);\r?$', '(?m)^      False: \(Small: Byte\);\r?$') }
  @{ Id = 'Rule: AlignDeclSemicolons does not pad the ; of typed constants (the value ends the line)'; Fix = 'polarity_rules6'; Set = @{}
     In = 'Box1: TRect = (...4); / Box22: TRect = (...400);'; Want = 'no blank before ;'; Show = 'Box\d'
     Must = @('(?m)^  Box1 : TRect = \(Left: 1; Top: 2; Right: 3; Bottom: 4\);\r?$')
     Not = @('(?m)^\s*Box\d+.*\) +;') }
  @{ Id = 'Rule: an anonymous method assigned in a statement does not leak a routine level'; Fix = 'polarity_rules6'; Set = @{}
     In = 'X := procedure begin After6; end; / X := procedure<NL>begin...end;'; Want = 'later statements and routines keep their indent'; Show = 'X:=|Alpha\.Beta|^\s*procedure After6|^\s*end\.'
     Must = @('(?m)^  Alpha\.Beta', '(?m)^procedure After6;\r?$', '(?m)^end\.\s*$') }
  @{ Id = 'Rule: a member . is never a shape-alignment anchor (Eta.Th stays one token)'; Fix = 'polarity_rules6'; Set = @{}
     In = 'Alpha.Beta := 1; Gamma.Delta := 2; Eta.Th := 3;'; Want = 'only := aligned'; Show = 'Beta|Delta|Eta.*:='
     Must = @('(?m)^\s*Eta\.Th +:= 3;\r?$', '(?m)^\s*Gamma\.Delta:= 2;\r?$')
     Not = @('Eta +\.') }
  @{ Id = 'Rule: a case label list holding a comment is not a colon-alignment peer'; Fix = 'polarity_rules6'; Set = @{}
     In = '3: {three} D := 1; / 4, {four} 5: D := 2;'; Want = 'no padding from the comment'; Show = '\{three\}|\{four\}'
     Must = @('(?m)^\s*3: \{three\} D:= 1;\r?$', '(?m)^\s*4, \{four\} 5: D:= 2;\r?$') }
  @{ Id = 'BreakIfBody ON: the else body after an end goes on its own line (end else D := 3;)'; Fix = 'polarity_rules6'; Set = @{}
     In = 'end else D := 3; / end else if D > 2 then D := 6;'; Want = 'end else / D:= 3;'; Show = 'end else|D:= [369];'
     Must = @('(?m)^  end else\r?\n    D:= 3;\r?$', '(?m)^  end else if D > 2 then\r?\n    D:= 6;\r?$', '(?m)^\s+end else D:= 9;\r?$') }
  @{ Id = 'BreakIfBody OFF: an if whose then part is a block keeps every body broken (end else D := 3;)'; Fix = 'polarity_rules6'; Set = @{ BreakIfBody = $F }
     In = 'end else D := 3;'; Want = 'end else / D:= 3;'; Show = 'end else|D:= [369];'
     Must = @('(?m)^  end else\r?\n    D:= 3;\r?$', '(?m)^\s+end else D:= 9;\r?$') }
  @{ Id = 'Rule: a call held open by a // comment continues one level under its statement'; Fix = 'polarity_rules6'; Set = @{}
     In = 'Writeln(Format(''%d %d'', [K, // keep<NL>D]));'; Want = 'D])); at statement + Indent'; Show = 'Writeln\(Format|^\s*D\]\)\);'
     Must = @('(?m)^  Writeln\(Format\(''%d %d'', \[K, // keep\r?\n    D\]\)\);\r?$') }
  @{ Id = 'TrimTrailing OFF: every trailing blank of a code line is kept'; Fix = 'polarity_rules6'; Set = @{ TrimTrailing = $F }
     In = 'D := 0;   (three trailing blanks)'; Want = 'D:= 0;   '; Show = 'D:= 0;'
     Must = @('(?m)^  D:= 0;   \r?$') }
  @{ Id = 'BreakCaseLabels ON: a brace comment in the label list stays with the FIRST label (owner 2026-11-02)'; Fix = 'polarity_comments'; Set = @{ BreakCaseLabels = $T }
     In = '4, {four}<NL>5: Inc(CmJ);'; Want = '4: {four} Inc(CmJ); / 5: Inc(CmJ);'; Show = '^\s*[4-7][,:]'
     Must = @('(?m)^\s*4\s*: \{four\} Inc\(CmJ\);\r?\n\s*5\s*: Inc\(CmJ\);\r?$', '(?m)^\s*6, // six\r?\n\s*7\s*: Inc\(CmJ\);\r?$') }
  @{ Id = 'PackStatements ON: an if / loop body line is never packed with the next statement'; Fix = 'polarity_stmts6'; Set = @{ PackStatements = $T }
     In = 'if C then<NL>PsA:= 1;<NL>PsB:= 2;<NL>PsC:= 3;'; Want = 'body alone, the next two packed'; Show = 'PsA:=|PsB:=|PsC:='
     Must = @('(?m)^\s*if C then\r?\n\s+PsA:= 1;\r?\n\s*PsB:= 2; PsC:= 3;\r?$', '(?m)^\s*for PsA:= 0 to 3 do\r?\n\s+PsB:= PsA;\r?\n\s*PsC:= 4;')
     Not = @('PsA:= 1; PsB', 'PsB:= PsA; PsC') }
  @{ Id = 'PackStatements ON + Break*Body OFF: a joined body line is never packed with the next statement'; Fix = 'polarity_stmts6'; Set = @{ PackStatements = $T; BreakIfBody = $F; BreakLoopBody = $F }
     In = 'if C then<NL>PsA:= 1;<NL>PsB:= 2;'; Want = 'if C then PsA:= 1; alone'; Show = 'PsA:=|PsB:=|PsC:='
     Must = @('(?m)^\s*if C then PsA:= 1;\r?$', '(?m)^\s*for PsA:= 0 to 3 do PsB:= PsA;\r?$') }
)

$questions = @()

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
