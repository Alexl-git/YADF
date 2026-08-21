# BreakLongExpressions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in YADF option that breaks an over-long line at every depth-0 operator -- one component per line, operator leading -- recursing into components that still overflow, and moving a trailing `then` / `do` to its own line at the header keyword's column.

**Architecture:** A depth-filtered scanner (`FindComponentBoundaries`) plus a recursive non-greedy breaker (`BreakComponents`) live beside the existing `FindOperatorPositionsAtTopLevel` / `BreakLineByOperators` inside `FormatSource`. `BreakLongLines` picks between the new and old breaker on the option. The existing greedy path is left byte-for-byte intact and still serves the option-off case.

**Tech Stack:** Delphi 13 Florence (RAD Studio 37.0), Object Pascal, Win64. Tests are PowerShell scripts driving the built `YADF.exe`. Compile gating uses `dcc64.exe`.

**Spec:** `docs/superpowers/specs/2026-08-21-break-long-expressions-design.md`

**Fallback:** `6e1f462` is the last known-good state (23/23 tests, three binaries built, lint clean). `git reset --hard 6e1f462` recovers it.

## Global Constraints

- **Encoding:** all `.pas` files are strict 7-bit ASCII, no BOM, CRLF line endings. Never introduce Unicode or LF.
- **Naming:** `TMyClass`, `FMyField`, `AMyParam` for parameters, matching surrounding code.
- **DocInsight required** on every public declaration: `///` XML (`<summary>`, `<param>`, `<returns>`, `<remarks>`). The functions here are nested inside `FormatSource` and are therefore private -- use `//` block comments matching their neighbours, not `///`.
- **Default is `False`.** The option must not alter output unless enabled. All 83 golden baselines stay byte-identical.
- **NEVER remove, reword, or relocate an existing `// dl:ok <rule>@<hash>` comment.** These are drag-lint reviewed-exception markers and are load-bearing project accounting. Before each commit, compare `(git show HEAD:<file> | Select-String 'dl:ok').Count` with the working-tree count and report both. Adding a new one is acceptable if justified -- say so explicitly.
- **Do NOT touch `YADF.Tokens.pas`** -- it is open in the RAD Studio IDE. `YADF.Layout.pas`, `YADF.Options.pas` and `YadfMain.pas` are closed and safe to edit on disk.
- **Build command:** `msbuild /t:Build /p:Config=Debug /p:Platform=Win64 YADF.dproj`, via the `delphi-build` skill recipe (3-line wrapper `.bat`: `rsvars` -> `cd` -> `msbuild`, launched from PowerShell `Start-Process -Wait` with output to a log, then read the log for `BUILD_EXITCODE=0` and no `[dcc] Error`). Do NOT use the mcpbuild MCP tool. Do NOT run `cmd.exe /c build.bat` from Bash (it hangs).
- **Pre-existing harmless diagnostics** -- not yours, not failures: `W1000` x3 (DelphiAST `SimpleParser.Lexer.pas`), `H2077` (`YADF.Layout.pas` ~line 1993).
- **Tests:** `pwsh -NoProfile -File <script>`. `Test\run_tests.ps1` must end `24 passed, 0 failed` once the new script exists (23 today + 1 new).
- **Test regexes:** use `\s*$`, never bare `$` -- YADF emits CRLF and `$` cannot match before `\r`.
- **Delphi symbol lookups:** query drag-lint BEFORE Grep -- `C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe query --name <Sym> --db "C:\Projects\YADF\_D-RAG\YADF.sqlite"`.
- **Reindex after symbol-changing builds:** `drag-lint index --all --only YADF`.
- **Commit granularity:** one commit per task. Do NOT `git push`. Do NOT run `.private\GITPush.bat`. The working tree has unrelated modified files -- leave them alone.

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `YADF.Options.pas` | Settings authority | Modify -- 3 insertions |
| `YADF.Layout.pas` | Formatting engine | Modify -- 3 nested functions + 1 branch |
| `YadfMain.pas` | CLI surface | Modify -- 2 flag branches, 2 help lines |
| `Test\test_break_expr.ps1` | Behaviour tests | Create |
| `CHANGELOG.md`, `Demo\Sample.pas` | Docs + showcase | Modify |

No new units. No UI files -- `TYadfOptionsFrame` code-builds from `OptionTable`, so both hosts get the checkbox automatically.

**Anchor note:** all `YADF.Layout.pas` line numbers below were accurate at authoring time. Earlier tasks shift them. Locate anchor text, never trust a number.

---

### Task 1: Option surface

Wires the option onto every surface without changing any output.

**Files:**
- Modify: `YADF.Options.pas:80` (record), `:542` (default), `:765` (table entry)
- Modify: `YadfMain.pas:890` (help), `YadfMain.pas:1317` (flags)
- Test: `Test\test_break_expr.ps1` (create)

**Interfaces:**
- Consumes: nothing.
- Produces: `TYadfOptions.BreakLongExpressions: Boolean`, default `False`. CLI `--break-expr` / `--no-break-expr`. INI key `BreakLongExpressions`.

- [ ] **Step 1: Write the failing test**

Create `Test\test_break_expr.ps1`:

```powershell
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh -NoProfile -File Test\test_break_expr.ps1`
Expected: FAIL on `help lists --break-expr`.

- [ ] **Step 3: Add the record field**

`YADF.Options.pas`, in `TYadfOptions`, after `BreakParamsOnePerLine` and before `Delphi10Compat`:

```pascal
    BreakParamsOnePerLine: Boolean      ;
    BreakLongExpressions : Boolean      ;
    Delphi10Compat       : Boolean      ;
```

Re-align the record's colon column; do not leave it ragged.

- [ ] **Step 4: Add the default**

`YADF.Options.pas`, in `DefaultOptions`, after `Result.BreakParamsOnePerLine:= False;`:

```pascal
  Result.BreakLongExpressions := False;
```

- [ ] **Step 5: Add the descriptor-table entry**

`YADF.Options.pas`, in `OptionTable`, immediately after the `BreakParamsOnePerLine` entry, in the `Reflow & whitespace` group:

```pascal
    MakeOpt('BreakLongExpressions', 'Reflow & whitespace', 'Break long expressions one component per line', 'When a line exceeds MaxLen, break it at every top-level operator -- one component per line, with the connecting operator LEADING each line ("and X" / "or Y"). '
      + 'A parenthesised group is one component and stays whole; a component that still does not fit is broken the same way, one indent step deeper. '
      + 'A trailing "then" or "do" moves to its own line at the column of the "if" / "while" that introduced it. '
      + 'Lines that already fit are never touched. Off by default -- long lines use the greedy breaker instead.', okBool, True, function(const O: TYadfOptions): Variant begin Result:= O.BreakLongExpressions end, procedure(var O: TYadfOptions; const V: Variant) begin O.BreakLongExpressions:= V end),
```

- [ ] **Step 6: Add the CLI flag branches**

`YadfMain.pas`, in `ParseFlags`, after the `--no-break-params` branch and before `--ini`:

```pascal
      else if AArgs[i] = '--break-expr' then
      begin
        AOpts.BreakLongExpressions:= True;
        Inc(i);
      end
      else if AArgs[i] = '--no-break-expr' then
      begin
        AOpts.BreakLongExpressions:= False;
        Inc(i);
      end
```

- [ ] **Step 7: Add the help lines**

`YadfMain.pas`, after the `--no-break-params` help line:

```pascal
  WriteStdoutLine(Format('  --break-expr          break a long line one component per line             [expr=%s]', [OnOff(AOpts.BreakLongExpressions)]));
  WriteStdoutLine('  --no-break-expr       use the greedy line breaker (default)');
```

- [ ] **Step 8: Build**

Per the `delphi-build` recipe. Expect `BUILD_EXITCODE=0`, no `[dcc] Error`.

- [ ] **Step 9: Run test to verify it passes**

Run: `pwsh -NoProfile -File Test\test_break_expr.ps1`
Expected: PASS.

- [ ] **Step 10: Verify no regression**

Run: `pwsh -NoProfile -File Test\run_tests.ps1`
Expected: `24 passed, 0 failed`.

- [ ] **Step 11: Commit**

```bash
git add YADF.Options.pas YadfMain.pas Test/test_break_expr.ps1
git commit -m "feat(options): add BreakLongExpressions option surface"
```

---

### Task 2: Depth-0 scanner and the recursive non-greedy breaker

The core. Adds `FindComponentBoundaries` (depth-0 operators only) and `BreakComponents` (one component per line, recursing into overflow), and branches `BreakLongLines` onto the option.

The scanner has no independently testable deliverable -- it is unreferenced until the breaker uses it -- so both land in one task.

**Files:**
- Modify: `YADF.Layout.pas` -- insert after `FindOperatorPositionsAtTopLevel` (ends ~`:5673`) and after `BreakLineByOperators` (ends ~`:5743`); branch inside `BreakLongLines` (~`:5764`)
- Test: `Test\test_break_expr.ps1` (extend)

**Interfaces:**
- Consumes: `IsAlphaNum`, `LeadingIndent`, `BreakLineByOperators`, `TLineScanState` (all existing, all nested in `FormatSource`).
- Produces:
  - `function FindComponentBoundaries(const Line: string): TArray<Integer>;` -- 1-based positions of `and`/`or`/`xor`/`+`/`-` at bracket depth 0.
  - `function BreakComponents(const ALine, ABaseIndent: string; ALevel: Integer): string;` -- the broken multi-line result.

- [ ] **Step 1: Write the failing test**

Append to `Test\test_break_expr.ps1` before `Finish`:

```powershell
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
MustMatch $flat '(?m)^\s+and DeltaFlagIsLong\s*$' 'flat: and leads component 4'

# RECURSION: a component that still overflows breaks again, ONE STEP DEEPER.
# Indent=2, so top-level components sit at 4 and their children at 6.
$deep = FmtBody '  if (Aa > 0) or (AlphaFlagIsLong and BetaFlagIsLong and GammaFlagIsLong and DeltaFlagIsLong) then Writeln(1);' '--break-expr' 46
$orLine  = ($deep -split "`r?`n" | Where-Object { $_ -match '^\s+or \(AlphaFlagIsLong' } | Select-Object -First 1)
$subLine = ($deep -split "`r?`n" | Where-Object { $_ -match '^\s+and BetaFlagIsLong' }   | Select-Object -First 1)
if (-not $orLine)  { Fail 'recursion: no top-level or component line' }
if (-not $subLine) { Fail 'recursion: over-long component was not broken again' }
$orInd  = ($orLine  -replace '\S.*$','').Length
$subInd = ($subLine -replace '\S.*$','').Length
if ($subInd -le $orInd) { Fail "recursion: sub-component indent $subInd must be deeper than parent $orInd" }

# A parenthesised condition: the GROUPS stay whole, only the top-level or breaks.
$paren = FmtBody '  if (AlphaFlagIsLong and BetaFlagIsLong) or (GammaFlagIsLong and DeltaFlagIsLong) then Writeln(1);' '--break-expr'
MustMatch $paren '(?m)^\s+if \(AlphaFlagIsLong and BetaFlagIsLong\)\s*$' 'paren: first group whole on the head line'
MustMatch $paren '(?m)^\s+or \(GammaFlagIsLong and DeltaFlagIsLong\)\s*$' 'paren: second group whole, or leading'

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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh -NoProfile -File Test\test_break_expr.ps1`
Expected: FAIL on `nogreedy: component 2 alone on its line` -- the greedy breaker packs them.

- [ ] **Step 3: Add the depth-0 scanner**

`YADF.Layout.pas`, immediately after `FindOperatorPositionsAtTopLevel` ends (the `end; // begin` before `LeadingIndent`):

```pascal
// Depth-0 sibling of FindOperatorPositionsAtTopLevel, for the
// one-component-per-line breaker. Returns only the connecting
// operators (` and ` ` or ` ` xor ` ` + ` ` - `) that sit at bracket
// depth ZERO -- these are the expression's component boundaries, so a
// parenthesised group is one component and is never split here.
// The existing scanner deliberately does NOT filter by depth (its
// AddIfWord calls never consult St.Depth); that is harmless for the
// greedy breaker, which picks one position, but would shatter groups
// under the break-at-every-boundary rule.
  function FindComponentBoundaries(const Line: string): TArray<Integer>;
  var
    Done     : Boolean       ;
    i        : Integer       ;
    Positions: TList<Integer>;
    St       : TLineScanState;
    procedure AddIfWordAtDepth0(Idx, Wlen: Integer; const W: string);
    begin
      if St.Depth <> 0 then
        Exit;
      if (Idx + Wlen - 1 > Length(Line)) then
        Exit;
      if not SameText(Copy(Line, Idx, Wlen), W) then
        Exit;
      if (Idx > 1) and IsAlphaNum(Line[Idx - 1]) then
        Exit;
      if (Idx + Wlen <= Length(Line)) and IsAlphaNum(Line[Idx + Wlen]) then
        Exit;
      Positions.Add(Idx);
    end;
  begin
    Positions:= TList<Integer>.Create;
    try
      St.Reset;
      Done:= False;
      i   := 1;
      while not Done do
      case St.SkipNonCode(Line, i) of
        seEndOfLine, seLineComment: Done:= True;
        seCode                    :
        begin
          if CharInSet(Line[i], ['(', '[', ')', ']']) then
          begin
            St.StepCode(Line, i);
            Continue;
          end;
          if (i > 1) and (Line[i - 1] = ' ') and (St.Depth = 0) then
          begin
            if CharInSet(Line[i], ['+', '-']) and (i + 1 <= Length(Line)) and (Line[i + 1] = ' ') then
            begin
              Positions.Add(i);
              Inc(i);
              Continue;
            end;
            AddIfWordAtDepth0(i, 2, 'or' );
            AddIfWordAtDepth0(i, 3, 'and');
            AddIfWordAtDepth0(i, 3, 'xor');
          end; // if
          Inc(i);
        end; // case
      end; // case
      Result:= Positions.ToArray;
    finally
      Positions.Free;
    end; // try
  end; // function
```

- [ ] **Step 4: Add the recursive breaker**

`YADF.Layout.pas`, immediately after `BreakLineByOperators` ends:

```pascal
// One component per line, operator leading, recursing into any
// component that still overflows.
//   1. A line that already fits is returned unchanged.
//   2. Split at EVERY depth-0 boundary -- deliberately NOT greedy. A
//      component sharing a line with another cannot be commented out
//      on its own, which is the whole point of the option.
//   3. The head (text before the first boundary) keeps the line's own
//      indent; every component goes to BaseIndent + Indent*(Level+1),
//      so nesting depth is visible as indent depth.
//   4. A component that still exceeds MaxLen recurses one level deeper.
//   5. No depth-0 boundary at all -> defer to the greedy breaker, which
//      can still split on an in-paren comma.
// A continuation line already begins with its operator; that leading
// operator is NOT a boundary, hence the MinAt guard.
  function BreakComponents(const ALine, ABaseIndent: string; ALevel: Integer): string;
  var
    Bounds: TArray<Integer>;
    i     : Integer        ;
    Ind   : string         ;
    k     : Integer        ;
    MinAt : Integer        ;
    OutVal: TStringBuilder ;
    Piece : string         ;
  begin
    if Length(ALine) <= AOpts.MaxLen then
      Exit(ALine);
    Bounds:= FindComponentBoundaries(ALine);
    MinAt := Length(LeadingIndent(ALine)) + 2;
    k     := 0;
    for i:= 0 to High(Bounds) do if Bounds[i] >= MinAt then
    begin
      Bounds[k]:= Bounds[i];
      Inc(k);
    end;
    SetLength(Bounds, k);
    if k = 0 then
      Exit(BreakLineByOperators(ALine));
    Ind   := ABaseIndent + StringOfChar(' ', AOpts.Indent * (ALevel + 1));
    OutVal:= TStringBuilder.Create;
    try
      OutVal.Append(TrimRight(Copy(ALine, 1, Bounds[0] - 1)));
      for i:= 0 to High(Bounds) do
      begin
        if i < High(Bounds) then
          Piece:= Copy(ALine, Bounds[i], Bounds[i + 1] - Bounds[i])
        else
          Piece:= Copy(ALine, Bounds[i], MaxInt);
        Piece:= Ind + Trim(Piece);
        OutVal.Append(CRLF);
        if Length(Piece) > AOpts.MaxLen then
          OutVal.Append(BreakComponents(Piece, ABaseIndent, ALevel + 1))
        else
          OutVal.Append(Piece);
      end; // for
      Result:= OutVal.ToString;
    finally
      OutVal.Free;
    end; // try
  end; // function
```

- [ ] **Step 5: Branch `BreakLongLines` onto the option**

`YADF.Layout.pas`, in `BreakLongLines`, replace:

```pascal
      for i:= 0 to Lines.Count - 1 do if (Length(Lines[i]) > AOpts.MaxLen) and not Locked[i] then
        Lines[i]:= BreakLineByOperators(Lines[i]);
```

with:

```pascal
      for i:= 0 to Lines.Count - 1 do if (Length(Lines[i]) > AOpts.MaxLen) and not Locked[i] then
        if AOpts.BreakLongExpressions then
          Lines[i]:= BreakComponents(Lines[i], LeadingIndent(Lines[i]), 0)
        else
          Lines[i]:= BreakLineByOperators(Lines[i]);
```

- [ ] **Step 6: Build, then run the test**

Build per the `delphi-build` recipe, then:
Run: `pwsh -NoProfile -File Test\test_break_expr.ps1`
Expected: PASS.

If `paren: second group whole, or leading` fails with the group split apart, `FindComponentBoundaries` is not filtering depth -- check that `St.StepCode` is reached for every bracket and that the `St.Depth = 0` guard is on the outer `if`, not only inside `AddIfWordAtDepth0` (the `+`/`-` branch needs it too).

- [ ] **Step 7: Verify no regression**

Run: `pwsh -NoProfile -File Test\run_tests.ps1`
Expected: `24 passed, 0 failed`, `golden_format: PASS (83 files unchanged + idempotent)`.

- [ ] **Step 8: Commit**

```bash
git add YADF.Layout.pas Test/test_break_expr.ps1
git commit -m "feat(layout): non-greedy component breaker, one per line"
```

---

### Task 3: Trailing `then` / `do` on their own line

Moves a trailing control keyword to its own line at the column of the header keyword that introduced it. Isolated deliberately: a lone `then` line is the piece most likely to fight `ReindentByDepth`, and this task can be reverted alone without losing Task 2.

**Files:**
- Modify: `YADF.Layout.pas` -- add `SplitTrailingHeaderKeyword` before `BreakComponents`; extend the `BreakLongLines` branch
- Test: `Test\test_break_expr.ps1` (extend)

**Interfaces:**
- Consumes: `BreakComponents`, `LeadingIndent`.
- Produces: `function SplitTrailingHeaderKeyword(const ALine: string; out ABody, AKeyword: string): Boolean;`

- [ ] **Step 1: Write the failing test**

Append to `Test\test_break_expr.ps1` before `Finish`:

```powershell
# ----- Task 3: trailing then / do on their own line, at the header column -----
# 'then' must land in EXACTLY the same column as its 'if'.
$thenOut = FmtBody '  if (AlphaFlagIsLong and BetaFlagIsLong) or (GammaFlagIsLong and DeltaFlagIsLong) then Writeln(1);' '--break-expr'
$ifCol   = ($thenOut -split "`r?`n" | Where-Object { $_ -match '^\s*if \(' }     | Select-Object -First 1) -replace '\S.*$',''
$thenCol = ($thenOut -split "`r?`n" | Where-Object { $_ -match '^\s*then\s*$' } | Select-Object -First 1) -replace '\S.*$',''
if (-not $thenCol) { Fail 'then: no standalone then line' }
if ($ifCol.Length -ne $thenCol.Length) { Fail "then: column $($thenCol.Length) must equal if column $($ifCol.Length)" }

# 'do' must land in EXACTLY the same column as its 'while'.
$doOut  = FmtBody '  while (AlphaFlagIsLong and BetaFlagIsLong) or (GammaFlagIsLong and DeltaFlagIsLong) do Writeln(1);' '--break-expr'
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
$caseOut = FmtBody '  if (AlphaFlagIsLong and BetaFlagIsLong) or (GammaFlagIsLong and DeltaFlagIsLong) THEN Writeln(1);' '--break-expr --no-lowercase-keywords'
MustMatch $caseOut '(?m)^\s*THEN\s*$' 'case: uppercase THEN preserved'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh -NoProfile -File Test\test_break_expr.ps1`
Expected: FAIL on `then: no standalone then line`.

- [ ] **Step 3: Add the keyword splitter**

`YADF.Layout.pas`, immediately before `BreakComponents`:

```pascal
// True when ALine is a control header whose LAST token is a trailing
// `then` or `do`, returning the line without it plus the keyword as
// written (source casing preserved -- LowercaseKeywords may be off).
// `until` is absent by design: it LEADS its condition, so there is
// nothing to move. A trailing `//` comment makes the keyword non-final
// and the line simply does not match, which is the safe outcome.
  function SplitTrailingHeaderKeyword(const ALine: string; out ABody, AKeyword: string): Boolean;
  const
    Trailing: array[0..1] of string = ('then', 'do');
  var
    i: Integer;
    T: string ;
    W: string ;
  begin
    Result  := False;
    ABody   := ALine;
    AKeyword:= '';
    T:= TrimRight(ALine);
    for i:= 0 to High(Trailing) do
    begin
      W:= Trailing[i];
      if (Length(T) > Length(W) + 1)
         and SameText(Copy(T, Length(T) - Length(W) + 1, Length(W)), W)
         and (T[Length(T) - Length(W)] = ' ') then
      begin
        AKeyword:= Copy(T, Length(T) - Length(W) + 1, Length(W));
        ABody   := TrimRight(Copy(T, 1, Length(T) - Length(W) - 1));
        Exit(True);
      end;
    end; // for
  end; // function
```

- [ ] **Step 4: Use it in the `BreakLongLines` branch**

Replace the Task 2 branch:

```pascal
        if AOpts.BreakLongExpressions then
          Lines[i]:= BreakComponents(Lines[i], LeadingIndent(Lines[i]), 0)
        else
          Lines[i]:= BreakLineByOperators(Lines[i]);
```

with:

```pascal
        if AOpts.BreakLongExpressions then
        begin
          HeadWS:= LeadingIndent(Lines[i]);
          if SplitTrailingHeaderKeyword(Lines[i], Body, Kw) then
            Lines[i]:= BreakComponents(Body, HeadWS, 0) + CRLF + HeadWS + Kw
          else
            Lines[i]:= BreakComponents(Lines[i], HeadWS, 0);
        end // if
        else
          Lines[i]:= BreakLineByOperators(Lines[i]);
```

Add `Body: string;`, `HeadWS: string;` and `Kw: string;` to `BreakLongLines`'s `var` block.

Note the keyword moves whenever the full line overflows, even if the body alone would fit -- moving it is what brings the line under `MaxLen`, and `BreakComponents` no-ops on a body that already fits.

- [ ] **Step 5: Build, then run the test**

Build per the `delphi-build` recipe, then:
Run: `pwsh -NoProfile -File Test\test_break_expr.ps1`
Expected: PASS.

If the `then` column is wrong, `ReindentByDepth` is re-indenting the lone keyword. Note `BreakLongLines` runs at `YADF.Layout.pas:5828`, AFTER the first `ReindentByDepth` (`:5826`) but BEFORE a second one at `:5832` that fires when `ReflowLines` is on -- which is the default. That second pass is the likely culprit; check what it does with a line whose only token is `then`.

- [ ] **Step 6: Verify no regression**

Run: `pwsh -NoProfile -File Test\run_tests.ps1`
Expected: `24 passed, 0 failed`, 83 goldens unchanged.

- [ ] **Step 7: Commit**

```bash
git add YADF.Layout.pas Test/test_break_expr.ps1
git commit -m "feat(layout): move trailing then/do to their own line"
```

---

### Task 4: Idempotency, round-trip and the compile gate

Proves the pass emits valid Delphi and is a fixed point. Catches what shape assertions cannot: output that looks right but does not compile, or that changes on a second format.

**Files:**
- Test: `Test\test_break_expr.ps1` (extend)

**Interfaces:**
- Consumes: everything from Tasks 1-3.
- Produces: nothing.

- [ ] **Step 1: Write the failing test**

Append to `Test\test_break_expr.ps1` before `Finish`:

```powershell
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
Remove-Item $o1,$o2 -Force -ErrorAction SilentlyContinue

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
```

- [ ] **Step 2: Run the test**

Run: `pwsh -NoProfile -File Test\test_break_expr.ps1`
Expected: PASS.

If **idempotency** fails, the pass is re-breaking its own output. The most likely cause is the `MinAt` guard in `BreakComponents` not excluding a continuation line's own leading operator, producing an empty head and an extra break on the second pass.

If **round-trip** (`--check`) fails, `FormatPreservesContent` rejected the output -- the pass dropped or altered a token. It is supposed to insert only CRLF and spaces; diff `$o1` against the input to find what moved.

If **compile** fails, read the `dcc64` error. A break placed inside a string literal or between a keyword and its operand is the usual cause.

- [ ] **Step 3: Verify the full suite**

Run: `pwsh -NoProfile -File Test\run_tests.ps1`
Expected: `24 passed, 0 failed`.

- [ ] **Step 4: Commit**

```bash
git add Test/test_break_expr.ps1
git commit -m "test: idempotency, round-trip and compile gate for --break-expr"
```

---

### Task 5: Documentation and showcase

**Files:**
- Modify: `CHANGELOG.md`, `Demo\Sample.pas`

**Interfaces:**
- Consumes: the shipped behaviour from Tasks 1-4.
- Produces: nothing.

- [ ] **Step 1: Add the CHANGELOG entry**

In the `## [Unreleased]` / `### Added` section of `CHANGELOG.md` (created during the BreakParamsOnePerLine work), above the existing entry:

```markdown
- **`BreakLongExpressions` (default false; `--break-expr`).** When a line
  exceeds `MaxLen`, breaks it at every top-level operator -- one component per
  line, with the connecting operator LEADING each line, matching the comma-first
  uses style. A parenthesised group is one component and stays whole; a
  component that still does not fit is broken the same way one indent step
  deeper, so nesting is visible. A trailing `then` / `do` moves to its own line
  at the column of the `if` / `while` that introduced it; `until` keeps its
  leading position. Lines that already fit are untouched. Applies to arithmetic
  as well as boolean expressions. Off by default -- long lines otherwise use the
  greedy breaker.
```

- [ ] **Step 2: Add the showcase block**

`Demo\Sample.pas`, after the `BreakParamsOnePerLine` showcase block (which ends with `ShowcaseFunc`):

```pascal
// --- BreakLongExpressions ('Break long expressions one component per line') -
// ON: a line OVER MaxLen breaks at every top-level operator, one component per
// line, with the operator LEADING -- the same doctrine as the comma-first uses
// clause. A parenthesised group is one component and stays whole; a component
// that still overflows breaks again one step deeper. Trailing 'then' / 'do'
// move to their own line, aligned with the 'if' / 'while' that opened them.
// The point is editability: one component per line means disabling one is a
// single-line comment-out. NOTE these lines only break when they exceed
// MaxLen -- lower the Max line length setting to watch it happen.
procedure ShowcaseLongExpressions(var Total: Integer);
begin
if (AlphaConditionFlagIsRatherLong and BetaConditionFlagIsAlsoLong) or (GammaConditionFlagGoesOn and DeltaConditionFlagToo) then
Total := AlphaLongOperandValue + BetaLongOperandValue + GammaLongOperandValue + DeltaLongOperandValue;
end;
```

- [ ] **Step 3: Verify the showcase renders**

Run: `.\Win64\Debug\EXE\YADF.exe --ini yadf.ini Demo\Sample.pas --break-expr --max-len 60 --stdout`
Expected: `ShowcaseLongExpressions` shows the `if` condition split one component per line with `or` leading, `then` alone on a line at the `if` column, and the arithmetic assignment split with `+` leading.

- [ ] **Step 4: Reindex**

Run: `C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe index --all --only YADF`
Expected: clean, 0 errors.

- [ ] **Step 5: Lint**

Run: `C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe lint-all --db "C:\Projects\YADF\_D-RAG\YADF.sqlite"`
Expected: `0 finding(s)`. If the new nested functions raise `deep-nesting` or `cyclomatic-complexity`, that is a real finding -- either simplify or add a `// dl:ok <rule>@<hash>` marker with a one-line justification, and say which you did.

- [ ] **Step 6: Commit**

```bash
git add CHANGELOG.md Demo/Sample.pas
git commit -m "docs: document BreakLongExpressions and add the demo showcase"
```

---

## Verification checklist

- [ ] `pwsh Test\run_tests.ps1` -> `24 passed, 0 failed`
- [ ] `Test\test_golden_format.ps1` -> all 83 goldens byte-identical (proves default-off)
- [ ] `Test\test_options.ps1` -> passes (descriptor table coherent)
- [ ] `lint-all` -> 0 findings on YADF, YADFOT and YADFSetup
- [ ] `dl:ok` counts did not decrease in any touched file
- [ ] YADFSetup shows the checkbox under **Reflow & whitespace**; toggling it changes the live preview
- [ ] `.pas` files remain 7-bit ASCII with CRLF
