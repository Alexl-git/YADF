# Break control-statement bodies onto their own line -- Implementation Plan

> ## EXECUTION STATUS (2026-07-22) -- COMPLETE + GREEN, DELIBERATELY UNCOMMITTED
>
> All 4 tasks implemented + reviewed (subagent-driven), plus a final Opus whole-branch review
> (verdict: Ready to merge) and a follow-up 2-line casing-fidelity fix. Full suite
> `pwsh Test\run_tests.ps1` = **20 passed / 0 failed / 0 skipped**; `golden_format` 81 files
> unchanged + idempotent; `compile_output` 48 compiled; the new `test_break_control.ps1` includes a
> dcc64 gate that compiles the SPLIT output (valid Delphi). Build Win64 Debug clean.
>
> **DO NOT commit / clean / revert the working tree.** Branch `experiment/autodoc-format` carries a
> large unrelated ~2200-line autodoc WIP (YADF.Layout.pas + YADF.Guard.pas + YADFSetup.dproj +
> build_all.bat); per the user's 2026-07-22 decision, break-control ships committed TOGETHER with that
> autodoc work at release. The feature's own uncommitted files:
> `YADF.Options.pas` (+26), `YADF.Layout.pas` (+269 purely additive -- zero WIP lines touched),
> `YadfMain.pas` (+36), `Test/test_break_control.ps1` (new), `CHANGELOG.md` (+14 `## [Unreleased]`).
> Design spec is already committed as `9ca0f55`; this plan file is uncommitted.
>
> SDD scratch (briefs, per-task snapshots, review packages, ledger `progress.md`):
> `C:\TEMP\claude\c--Projects-YADF\<session>\scratchpad\sdd-break-control\`.
> Optional open follow-ups (non-blocking): a direct test for the open-block-comment non-goal (only the
> `//` twin is asserted); the else-leading-with-nonempty-body branch is defensive/rarely-reached.
>
> Auto-memory: [[project_yadf_break_control_bodies]].

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three opt-in Boolean options -- `BreakLoopBody`, `BreakWithBody`, `BreakIfBody` -- that force a single-line control statement's body onto its own indented line.

**Architecture:** A single new string-level pass `BreakControlBodies` in `YADF.Layout.pas` (the structural mirror of `CollapseShortBlocks`) splits `for`/`while`/`with ... do Stmt;` after `do` and `if ... then/else` after `then`/around `else`, then relies on the existing `ReindentByDepth` to indent the freed body. Options are table-driven (`OptionTable`), so INI + YADFSetup + YADFOT surfaces are wired automatically; only the record fields, defaults, table entries, CLI flags, and the pass itself are hand-written.

**Tech Stack:** Delphi 13 (Studio 37) Object Pascal, Win64 Debug build via msbuild/rsvars, PowerShell (`pwsh`) test suite driven by `Test\run_tests.ps1`.

## Global Constraints

- **COMMITS ARE DEFERRED (release decision 2026-07-22):** the working tree already carries a large uncommitted `autodoc-format` WIP (`YADF.Layout.pas` +~2200 lines, plus `YADF.Guard.pas`, `YADFSetup.dproj`, `build_all.bat`). This feature will be committed **together with that WIP at release time**, not per task. **Skip every `git commit` step below.** Each task ends at its green test run. Do NOT `git add`/`git commit`, do NOT stash, do NOT revert the WIP. Edit surgically (unique `Edit` `old_string`s) so the WIP is never disturbed. The plan's line anchors were written against the current on-disk (WIP) `Layout.pas`, so they match the working tree.
- **Encoding:** all `.pas` files are strict 7-bit ASCII, CRLF line endings, no BOM, no Unicode. Preserve exactly on every edit.
- **Compiler floor:** code must compile on Delphi XE8 / 10.2.3 as well as 13 -- **no inline `var` declarations**; hoist all locals into a `var` block (match the existing `CurR/NextT` hoist pattern in `ReflowLineBreaks`).
- **Defaults:** all three new options default **False**; existing golden output must be byte-for-byte unchanged.
- **Option names (verbatim):** `BreakLoopBody`, `BreakWithBody`, `BreakIfBody`. CLI flags: `--break-loop`/`--no-break-loop`, `--break-with`/`--no-break-with`, `--break-if`/`--no-break-if`.
- **Content-neutral:** the pass inserts only CRLF + leading whitespace; it never adds, drops, or edits a string literal, comment, or directive (so the Stage-6 Guard passes with no tolerance change).
- **Group:** the three options belong to the existing `Reflow & whitespace` option group.
- **Build before test:** `Test\run_tests.ps1` runs against `Win64\Debug\EXE\YADF.exe` and warns if the exe is older than any `YADF*.pas`. Rebuild Win64 Debug (via the `delphi-build` skill) before running the suite in every task.

Canonical build (from the `delphi-build` skill -- write a 3-line wrapper `.bat` and run via `Start-Process -Wait`, then read the log for `BUILD_EXITCODE=0` and no `[dcc] Error`):

```
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
cd /d C:\Projects\YADF
msbuild /t:Build /p:Config=Debug /p:Platform=Win64 YADF.dproj
```

---

## File Structure

- **Modify** `YADF.Options.pas`
  - `TYadfOptions` record: add `BreakLoopBody`, `BreakWithBody`, `BreakIfBody: Boolean;`
  - `DefaultOptions`: three `:= False;` lines
  - `OptionTable`: three `MakeOpt(...)` entries in the `Reflow & whitespace` group
- **Modify** `YADF.Layout.pas`
  - Add `function BreakControlBodies(const S: string; const AOpts: TYadfOptions): string;` (implementation section, near `CollapseShortBlocks`)
  - Call it in `FormatSource`, Stage 3, after the reflow/pack `if..else` block
- **Modify** `YadfMain.pas`
  - Six `else if` CLI parse entries + three `--help` lines
- **Create** `Test\test_break_control.ps1` (auto-discovered by `run_tests.ps1`; no registration needed)
- **Create** `Test\Cases\control_bodies.pas` (fixture)
- **Modify** `CHANGELOG.md`

No new units; no interface-section additions (the pass is a private implementation helper, like `CollapseShortBlocks`).

---

## Task 1: Options plumbing + CLI flags

Wire the three options onto every surface. No formatting behavior yet (the pass is added in Task 2), so a `--break-loop` run is accepted but produces identical output. Independently testable: the flags are accepted, appear in `--help`, and land in a generated `yadf.ini`.

**Files:**
- Modify: `YADF.Options.pas` (record ~line 60-64, defaults ~line 226-229, table ~line 545-563)
- Modify: `YadfMain.pas` (help ~line 827-830, parse ~line 1207-1216)
- Create: `Test\test_break_control.ps1`

**Interfaces:**
- Produces: `TYadfOptions.BreakLoopBody`, `.BreakWithBody`, `.BreakIfBody: Boolean` (all default False); CLI flags `--break-loop|--no-break-loop`, `--break-with|--no-break-with`, `--break-if|--no-break-if`.

- [ ] **Step 1: Write the failing test** -- create `Test\test_break_control.ps1`

```powershell
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

Finish 'break_control'
```

- [ ] **Step 2: Run it to verify it fails**

Build is not required to see the first failure (the exe predates the flags). Run:
`pwsh -NoProfile -File Test\test_break_control.ps1`
Expected: FAIL at `help lists --break-loop` (or `--break-loop accepted` shows `unknown option`).

- [ ] **Step 3: Add the record fields** -- `YADF.Options.pas`, in `TYadfOptions`, after `CollapseShortBlocks: Boolean;` (line 63):

```pascal
    CollapseShortBlocks: Boolean;
    BreakLoopBody      : Boolean;
    BreakWithBody      : Boolean;
    BreakIfBody        : Boolean;
    Delphi10Compat     : Boolean;
```

- [ ] **Step 4: Add the defaults** -- `DefaultOptions`, after `Result.CollapseShortBlocks:= False;` (line 229):

```pascal
  Result.CollapseShortBlocks:= False  ;
  Result.BreakLoopBody      := False  ;
  Result.BreakWithBody      := False  ;
  Result.BreakIfBody        := False  ;
  Result.Delphi10Compat     := False  ;
```

- [ ] **Step 5: Add the table entries** -- `OptionTable`, immediately after the `CollapseShortBlocks` `MakeOpt(...)` entry (ends at line 563), still inside the `Reflow & whitespace` group:

```pascal
    MakeOpt('BreakLoopBody', 'Reflow & whitespace', 'Break loop body onto its own line',
      'Force the body of a single-line for/while loop onto its own indented line ' +
      '("while X do Dec(k);" -> "while X do" + newline + "  Dec(k);"). A begin block, ' +
      'a nested control header, or a body with a trailing comment is left alone. Off by default.',
      okBool, True,
      function(const O: TYadfOptions): Variant begin Result := O.BreakLoopBody end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.BreakLoopBody := V end),
    MakeOpt('BreakWithBody', 'Reflow & whitespace', 'Break with body onto its own line',
      'Force the body of a single-line with..do statement onto its own indented line. ' +
      'Same guard rails as BreakLoopBody (begin/nested-header/comment bodies left alone). Off by default.',
      okBool, True,
      function(const O: TYadfOptions): Variant begin Result := O.BreakWithBody end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.BreakWithBody := V end),
    MakeOpt('BreakIfBody', 'Reflow & whitespace', 'Break if/then/else body onto its own line',
      'Force the then/else body of a single-line if statement onto its own indented line ' +
      '("if X then A else B;" -> "if X then" / "  A" / "else" / "  B;"). "else if" chains stay ' +
      'glued; a begin/nested-header/comment body is left alone. Off by default.',
      okBool, True,
      function(const O: TYadfOptions): Variant begin Result := O.BreakIfBody end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.BreakIfBody := V end),
```

- [ ] **Step 6: Add the CLI parse entries** -- `YadfMain.pas`, after the `--no-collapse-blocks` block (ends line 1216), before the `--ini` handler:

```pascal
      else if AArgs[i] = '--break-loop' then
      begin
        AOpts.BreakLoopBody:= True;
        Inc(i);
      end
      else if AArgs[i] = '--no-break-loop' then
      begin
        AOpts.BreakLoopBody:= False;
        Inc(i);
      end
      else if AArgs[i] = '--break-with' then
      begin
        AOpts.BreakWithBody:= True;
        Inc(i);
      end
      else if AArgs[i] = '--no-break-with' then
      begin
        AOpts.BreakWithBody:= False;
        Inc(i);
      end
      else if AArgs[i] = '--break-if' then
      begin
        AOpts.BreakIfBody:= True;
        Inc(i);
      end
      else if AArgs[i] = '--no-break-if' then
      begin
        AOpts.BreakIfBody:= False;
        Inc(i);
      end
```

- [ ] **Step 7: Add the help lines** -- `YadfMain.pas`, after the `--no-collapse-blocks` help line (line 830):

```pascal
  WriteStdoutLine(Format('  --break-loop          break for/while body onto its own line             [loop=%s]', [OnOff(AOpts.BreakLoopBody)]));
  WriteStdoutLine('  --no-break-loop       keep the loop body inline (default)');
  WriteStdoutLine(Format('  --break-with          break with..do body onto its own line              [with=%s]', [OnOff(AOpts.BreakWithBody)]));
  WriteStdoutLine('  --no-break-with       keep the with body inline (default)');
  WriteStdoutLine(Format('  --break-if            break if then/else body onto its own line          [if=%s]', [OnOff(AOpts.BreakIfBody)]));
  WriteStdoutLine('  --no-break-if         keep the if/then/else body inline (default)');
```

- [ ] **Step 8: Build Win64 Debug** (via `delphi-build` skill). Expected: `BUILD_EXITCODE=0`, no `[dcc] Error`.

- [ ] **Step 9: Run the test to verify it passes**

Run: `pwsh -NoProfile -File Test\test_break_control.ps1`
Expected: PASS (`break_control: ... OK`).

- [ ] **Step 10: Confirm no regressions** -- `pwsh -NoProfile -File Test\run_tests.ps1`
Expected: all suites PASS/SKIP, `0 failed` (goldens unchanged; defaults are all False).

- [ ] **Step 11: Commit**

```bash
git add YADF.Options.pas YadfMain.pas Test/test_break_control.ps1
git commit -m "feat: add BreakLoopBody/BreakWithBody/BreakIfBody options (plumbing + CLI flags)"
```

---

## Task 2: `BreakControlBodies` pass -- for/while/with (do-split)

Add the pass and its `do`-splitting for `for`/`while` (`BreakLoopBody`) and `with` (`BreakWithBody`), and wire it into the pipeline. `if` is added in Task 3.

**Files:**
- Modify: `YADF.Layout.pas` (add function near `CollapseShortBlocks` ~line 2085; call site ~after line 4637)
- Modify: `Test\test_break_control.ps1`
- Create: `Test\Cases\control_bodies.pas`

**Interfaces:**
- Consumes: `TYadfOptions.BreakLoopBody`, `.BreakWithBody`, `.BreakIfBody` (Task 1); `ComputeBlockCommentLock`, `ReindentByDepth`, `CRLF` (existing in `YADF.Layout.pas`).
- Produces: `function BreakControlBodies(const S: string; const AOpts: TYadfOptions): string;`

- [ ] **Step 1: Write the failing test** -- append to `Test\test_break_control.ps1` (before the final `Finish`):

```powershell
# ----- Task 2: for/while/with do-split -----
$src = Join-Path $PSScriptRoot 'Cases\control_bodies.pas'

function Fmt([string]$flags) {
  $tmp = Join-Path $env:TEMP ('bctl_' + ([Math]::Abs($flags.GetHashCode())) + '.out')
  & $exe --ini $ini $src @($flags -split ' ') --o $tmp | Out-Null
  $out = Get-Content $tmp -Raw
  Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  return $out
}

# DEFAULT: bodies stay inline.
$off = Fmt '--no-break-loop --no-break-with --no-break-if'
MustMatch $off 'while .*do Dec\(k\);'   'off: while body inline'
MustMatch $off 'with Rec do X := 1;'    'off: with body inline'

# --break-loop: for/while bodies drop to their own line; with untouched.
$loop = Fmt '--break-loop'
MustMatch    $loop '(?m)do\s*$'                 'loop: header ends at do'
MustMatch    $loop '(?m)^\s+Dec\(k\);'          'loop: while body on own line'
MustMatch    $loop '(?m)^\s+Sum := Sum \+'      'loop: for body on own line'
MustMatch    $loop 'with Rec do X := 1;'        'loop: with STILL inline'

# --break-with: only with splits.
$wth = Fmt '--break-with'
MustMatch    $wth '(?m)^\s+X := 1;'             'with: body on own line'
MustMatch    $wth 'while .*do Dec\(k\);'        'with: while STILL inline'

# begin body + nested header are LEFT ALONE under --break-loop.
MustMatch    $loop 'while HasNext do begin'     'loop: begin body untouched'
MustMatch    $loop 'while A do while B do Ping;' 'loop: nested header untouched'

# idempotency for each single flag.
foreach ($f in @('--break-loop','--break-with')) {
  $o1 = Join-Path $env:TEMP 'bctl1.pas'; $o2 = Join-Path $env:TEMP 'bctl2.pas'
  & $exe --ini $ini $src $f --o $o1 | Out-Null
  & $exe --ini $ini $o1  $f --o $o2 | Out-Null
  if ((Get-FileHash $o1).Hash -ne (Get-FileHash $o2).Hash) { Fail "idempotent: $f" }
  $chk = & $exe --ini $ini --check $o1 2>&1
  if ("$chk" -notmatch 'PASS') { Fail "roundtrip: $f" }
  Remove-Item $o1,$o2 -Force -ErrorAction SilentlyContinue
}
```

- [ ] **Step 2: Create the fixture** -- `Test\Cases\control_bodies.pas` (strict ASCII, CRLF):

```pascal
unit control_bodies;

interface

implementation

procedure Demo;
var
  k, i, Sum: Integer;
begin
  k := 3;
  while k > 0 do Dec(k);
  Sum := 0;
  for i := 0 to 9 do Sum := Sum + i;
  with Rec do X := 1;
  if Sum > 0 then DoIt else DoOther;
  if k = 0 then Reset;
  while HasNext do begin Advance; Tally; end;
  while A do while B do Ping;
end;

end.
```

(`Rec.X`, `DoIt`, `DoOther`, `Reset`, `HasNext`, `Advance`, `Tally`, `A`, `B`, `Ping` need not resolve -- the fixture is fed to the formatter, not compiled here. Task 4 adds a compiling variant for the compile gate.)

- [ ] **Step 3: Run the test to verify it fails**

Run: `pwsh -NoProfile -File Test\test_break_control.ps1`
Expected: FAIL at `loop: while body on own line` (the pass does not exist; `--break-loop` is inert).

- [ ] **Step 4: Add the pass** -- `YADF.Layout.pas`, insert **before** `CollapseShortBlocks` (line 2085):

```pascal
/// <summary>Forces the body of a single-line control statement onto its own
/// indented line: for/while/with `... do Stmt;` (BreakLoopBody / BreakWithBody)
/// and if `... then A else B;` (BreakIfBody, added in Task 3). Structural mirror
/// of CollapseShortBlocks. Content-neutral (inserts only CRLF + whitespace);
/// ReindentByDepth (called by the pipeline right after) fixes the body depth.
/// A begin block, a body starting with a nested control header, or a line with a
/// top-level line comment / open block comment is left unchanged. Idempotent.</summary>
function BreakControlBodies(const S: string; const AOpts: TYadfOptions): string;
var
  Lines : TStringList    ;
  Lock  : TArray<Boolean>;
  Out_  : TStringBuilder ;
  i     : Integer        ;
  Cur   : string         ;
  T     : string         ;
  Indent: string         ;
  W     : TArray<string> ;
  BefP  : TArray<Integer>;
  AftP  : TArray<Integer>;
  Disq  : Boolean        ;
  m     : Integer        ;
  DoIx  : Integer        ;
  Header: string         ;
  Body  : string         ;

  function StartsWordCI(const L, Wd: string): Boolean;
  var
    Tr: string;
  begin
    Tr:= TrimLeft(L);
    if Length(Tr) < Length(Wd) then Exit(False);
    if not SameText(Copy(Tr, 1, Length(Wd)), Wd) then Exit(False);
    if Length(Tr) > Length(Wd) then
      Result:= not CharInSet(Tr[Length(Wd) + 1], ['a'..'z', 'A'..'Z', '0'..'9', '_'])
    else
      Result:= True;
  end;

// A body segment that qualifies for splitting: non-empty, not a begin/asm block,
// not a nested control header (those are the documented non-goals).
  function IsSimpleBody(const B: string): Boolean;
  var
    Tb: string;
  begin
    Tb:= TrimLeft(B);
    if Tb = '' then Exit(False);
    if StartsWordCI(Tb, 'begin' ) or StartsWordCI(Tb, 'asm'   ) then Exit(False);
    if StartsWordCI(Tb, 'if'    ) or StartsWordCI(Tb, 'while' ) or StartsWordCI(Tb, 'for'   ) or
       StartsWordCI(Tb, 'with'  ) or StartsWordCI(Tb, 'case'  ) or StartsWordCI(Tb, 'repeat') or
       StartsWordCI(Tb, 'try'   ) then Exit(False);
    Result:= True;
  end;

// Scans L left-to-right and records every whole-word do/then/else that occurs
// at paren/bracket depth 0 outside strings and comments. ADisq is set when a
// top-level `//` starts or a block comment is left open at end of line -- either
// forbids splitting (mirrors CurBlocksMerge / HasLineCommentOrOpenBlock).
  procedure ScanTop(const L: string; out AW: TArray<string>;
    out ABef, AAft: TArray<Integer>; out ADisq: Boolean);
  var
    p, n, ws    : Integer;
    depth       : Integer;
    inStr       : Boolean;
    inBlk       : Boolean;
    inPar       : Boolean;
    wrd         : string ;
    cnt         : Integer;

    function IsIdent(ch: Char): Boolean;
    begin
      Result:= CharInSet(ch, ['a'..'z', 'A'..'Z', '0'..'9', '_']);
    end;

    procedure AddHit(const AWord: string; ABp, AAp: Integer);
    begin
      if cnt = Length(AW) then
      begin
        SetLength(AW  , cnt * 2 + 4);
        SetLength(ABef, cnt * 2 + 4);
        SetLength(AAft, cnt * 2 + 4);
      end;
      AW[cnt]:= AWord; ABef[cnt]:= ABp; AAft[cnt]:= AAp; Inc(cnt);
    end;

  begin
    ADisq:= False;
    cnt  := 0;
    SetLength(AW, 0); SetLength(ABef, 0); SetLength(AAft, 0);
    n    := Length(L);
    p    := 1; depth:= 0; inStr:= False; inBlk:= False; inPar:= False;
    while p <= n do
    begin
      if inStr then
      begin
        if L[p] = '''' then
          if (p < n) and (L[p + 1] = '''') then Inc(p)
          else inStr:= False;
        Inc(p); Continue;
      end;
      if inBlk then
      begin
        if L[p] = '}' then inBlk:= False;
        Inc(p); Continue;
      end;
      if inPar then
      begin
        if (L[p] = '*') and (p < n) and (L[p + 1] = ')') then begin inPar:= False; Inc(p); end;
        Inc(p); Continue;
      end;
      if L[p] = '''' then begin inStr:= True; Inc(p); Continue; end;
      if L[p] = '{'  then begin inBlk:= True; Inc(p); Continue; end;
      if (L[p] = '(') and (p < n) and (L[p + 1] = '*') then begin inPar:= True; Inc(p, 2); Continue; end;
      if (L[p] = '/') and (p < n) and (L[p + 1] = '/') then begin ADisq:= True; Exit; end;
      if (L[p] = '(') or (L[p] = '[') then begin Inc(depth); Inc(p); Continue; end;
      if (L[p] = ')') or (L[p] = ']') then begin if depth > 0 then Dec(depth); Inc(p); Continue; end;
      if IsIdent(L[p]) and ((p = 1) or not IsIdent(L[p - 1])) then
      begin
        ws := p;
        wrd:= '';
        while (p <= n) and IsIdent(L[p]) do begin wrd:= wrd + L[p]; Inc(p); end;
        if (depth = 0) and (SameText(wrd, 'do') or SameText(wrd, 'then') or SameText(wrd, 'else')) then
          AddHit(LowerCase(wrd), ws, p);
        Continue;
      end;
      Inc(p);
    end;
    if inBlk or inPar then ADisq:= True;
    SetLength(AW, cnt); SetLength(ABef, cnt); SetLength(AAft, cnt);
  end;

  procedure OutLine(const L: string);
  begin
    Out_.Append(L); Out_.Append(CRLF);
  end;

begin
  Lines:= TStringList.Create;
  try
    Lines.LineBreak:= CRLF;
    Lines.Text     := S;
    Lock:= ComputeBlockCommentLock(Lines);
    Out_:= TStringBuilder.Create;
    try
      for i:= 0 to Lines.Count - 1 do
      begin
        Cur:= Lines[i];
        T  := TrimLeft(Cur);
        Indent:= Copy(Cur, 1, Length(Cur) - Length(T));
        // Loops / with: split after the first top-level `do`.
        if (not Lock[i]) and
           ( ((StartsWordCI(T, 'for') or StartsWordCI(T, 'while')) and AOpts.BreakLoopBody) or
             (StartsWordCI(T, 'with') and AOpts.BreakWithBody) ) then
        begin
          ScanTop(Cur, W, BefP, AftP, Disq);
          if not Disq then
          begin
            DoIx:= -1;
            for m:= 0 to High(W) do if W[m] = 'do' then begin DoIx:= m; Break; end;
            if DoIx >= 0 then
            begin
              Header:= TrimRight(Copy(Cur, 1, AftP[DoIx] - 1));
              Body  := Trim(Copy(Cur, AftP[DoIx], Length(Cur)));
              if IsSimpleBody(Body) then
              begin
                OutLine(Header);
                OutLine(Indent + Body);
                Continue;
              end;
            end;
          end;
        end;
        // (if/then/else handled in Task 3)
        OutLine(Cur);
      end;
      Result:= Out_.ToString;
    finally
      Out_.Free;
    end;
  finally
    Lines.Free;
  end;
end; // function
```

- [ ] **Step 5: Wire it into the pipeline** -- `YADF.Layout.pas`, in `FormatSource`, immediately after the reflow/pack `if..else` block closes (`end; // else`, line 4637) and before the `EffMaxBlanks` computation (line 4638):

```pascal
        end; // else
        // Break single-line control-statement bodies onto their own line when
        // any Break* flag is on. Runs after the reflow/pack block (so it acts on
        // the settled line shape and wins over PackShortBodies) and before the
        // Stage-4 alignment passes (splitting changes line adjacency). Re-indent
        // so the freed body gets its structural +1 depth.
        if AOpts.BreakLoopBody or AOpts.BreakWithBody or AOpts.BreakIfBody then
        begin
          Result:= BreakControlBodies(Result, AOpts);
          Result:= ReindentByDepth(Result, AOpts.Indent, AOpts.IndentComments);
        end;
        EffMaxBlanks:= AOpts.MaxBlankLines;
```

- [ ] **Step 6: Build Win64 Debug** (via `delphi-build` skill). Expected: `BUILD_EXITCODE=0`, no `[dcc] Error`.

- [ ] **Step 7: Run the test to verify it passes**

Run: `pwsh -NoProfile -File Test\test_break_control.ps1`
Expected: PASS through the Task 2 section.

- [ ] **Step 8: Confirm no regressions** -- `pwsh -NoProfile -File Test\run_tests.ps1`
Expected: `0 failed`. If a golden shifted, defaults leaked -- verify the pipeline guard is `if ... BreakLoopBody or BreakWithBody or BreakIfBody`.

- [ ] **Step 9: Commit**

```bash
git add YADF.Layout.pas Test/test_break_control.ps1 Test/Cases/control_bodies.pas
git commit -m "feat: BreakControlBodies pass -- for/while/with body split (BreakLoopBody/BreakWithBody)"
```

---

## Task 3: `BreakIfBody` -- if/then/else + else-if chains

Extend `BreakControlBodies` to split `if ... then/else` bodies, gluing `else if` and handling already-multiline `else X;` lines. Break after `then`, before/after `else`.

**Files:**
- Modify: `YADF.Layout.pas` (`BreakControlBodies` body -- add the if/else branch; add locals)
- Modify: `Test\test_break_control.ps1`

**Interfaces:**
- Consumes: `ScanTop`, `IsSimpleBody`, `StartsWordCI`, `OutLine` (Task 2, same function scope).
- Produces: no new signature; extends `BreakControlBodies` behavior for `BreakIfBody`.

- [ ] **Step 1: Write the failing test** -- append to `Test\test_break_control.ps1` (before `Finish`):

```powershell
# ----- Task 3: if/then/else split -----
$iff = Fmt '--break-if'
# "if Sum > 0 then DoIt else DoOther;" -> four lines.
MustMatch    $iff '(?m)^\s*if Sum > 0 then\s*$'  'if: header ends at then'
MustMatch    $iff '(?m)^\s+DoIt\s*$'             'if: then-body on own line (no semicolon)'
MustMatch    $iff '(?m)^\s*else\s*$'             'if: else on own line'
MustMatch    $iff '(?m)^\s+DoOther;'             'if: else-body on own line'
# "if k = 0 then Reset;" (no else) -> two lines.
MustMatch    $iff '(?m)^\s*if k = 0 then\s*$'    'if: no-else header'
MustMatch    $iff '(?m)^\s+Reset;'               'if: no-else body split'
# loops untouched when only --break-if is on.
MustMatch    $iff 'while .*do Dec\(k\);'         'if: while STILL inline'

# else-if chain stays glued: format an inline chain.
$chainSrc = Join-Path $env:TEMP 'bctl_chain.pas'
@'
unit c; interface implementation
procedure Go(X: Integer);
begin
  if X = 1 then A else if X = 2 then B else C;
end;
end.
'@ | Set-Content $chainSrc -Encoding ascii
$chainOut = Join-Path $env:TEMP 'bctl_chain.out'
& $exe --ini $ini $chainSrc --break-if --o $chainOut | Out-Null
$co = Get-Content $chainOut -Raw
MustMatch    $co '(?m)^\s*else if X = 2 then\s*$' 'chain: else-if glued'
MustMatch    $co '(?m)^\s+B\s*$'                  'chain: else-if body split'
MustMatch    $co '(?m)^\s*else\s*$'               'chain: final else on own line'
MustMatch    $co '(?m)^\s+C;'                     'chain: final body split'
MustNotMatch $co 'then A'                         'chain: no body left on a then line'
# idempotent + compiles-round-trip.
$c2 = Join-Path $env:TEMP 'bctl_chain2.out'
& $exe --ini $ini $chainOut --break-if --o $c2 | Out-Null
if ((Get-FileHash $chainOut).Hash -ne (Get-FileHash $c2).Hash) { Fail 'idempotent: --break-if chain' }
Remove-Item $chainSrc,$chainOut,$c2 -Force -ErrorAction SilentlyContinue
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `pwsh -NoProfile -File Test\test_break_control.ps1`
Expected: FAIL at `if: header ends at then` (if-splitting not implemented; `--break-if` is inert).

- [ ] **Step 3: Add the if/else branch** -- `YADF.Layout.pas`, in `BreakControlBodies`. First add these locals to the function's `var` block:

```pascal
  Segs  : TStringList    ;
  isElse: Boolean        ;
  Cursor: Integer        ;
  k      : Integer       ;
  Ok    : Boolean        ;
  s2    : Integer        ;
```

Then replace the `// (if/then/else handled in Task 3)` comment line with the branch below (it sits between the do-split `end;` and the fallthrough `OutLine(Cur);`):

```pascal
        // if / else: split after `then`, before/after each top-level `else`;
        // "else if ... then" stays glued as one header line.
        isElse:= StartsWordCI(T, 'else');
        if (not Lock[i]) and AOpts.BreakIfBody and (StartsWordCI(T, 'if') or isElse) then
        begin
          ScanTop(Cur, W, BefP, AftP, Disq);
          if not Disq then
          begin
            Segs:= TStringList.Create;
            try
              Segs.LineBreak:= CRLF;
              Ok:= True;
              // Establish the first header segment + cursor.
              if not isElse then
              begin
                if (Length(W) = 0) or (W[0] <> 'then') then Ok:= False
                else
                begin
                  Segs.Add(Trim(Copy(Cur, 1, AftP[0] - 1)));   // "if COND then"
                  Cursor:= AftP[0];
                  k     := 1;
                end;
              end
              else if (Length(W) >= 2) and (W[0] = 'else') and (W[1] = 'then') then
              begin
                Segs.Add(Trim(Copy(Cur, 1, AftP[1] - 1)));      // "else if COND then"
                Cursor:= AftP[1];
                k     := 2;
              end
              else if (Length(W) >= 1) and (W[0] = 'else') then
              begin
                Segs.Add('else');
                Cursor:= AftP[0];
                k     := 1;
              end
              else
                Ok:= False;
              // Walk the remaining else hits.
              while Ok and (k <= High(W)) do
              begin
                if W[k] <> 'else' then begin Ok:= False; Break; end; // stray then = nested if body
                Body:= Trim(Copy(Cur, Cursor, BefP[k] - Cursor));
                if not IsSimpleBody(Body) then begin Ok:= False; Break; end;
                Segs.Add(Body);
                if (k + 1 <= High(W)) and (W[k + 1] = 'then') then
                begin
                  Segs.Add(Trim(Copy(Cur, BefP[k], AftP[k + 1] - BefP[k])));  // "else if COND then"
                  Cursor:= AftP[k + 1];
                  k     := k + 2;
                end
                else
                begin
                  Segs.Add('else');
                  Cursor:= AftP[k];
                  k     := k + 1;
                end;
              end;
              if Ok then
              begin
                Body:= Trim(Copy(Cur, Cursor, Length(Cur)));   // trailing body
                if IsSimpleBody(Body) then Segs.Add(Body) else Ok:= False;
              end;
              if Ok and (Segs.Count >= 2) then
              begin
                for s2:= 0 to Segs.Count - 1 do
                  OutLine(Indent + Segs[s2]);
                Continue;   // line handled; skip fallthrough
              end;
            finally
              Segs.Free;
            end;
          end;
        end;
        OutLine(Cur);
```

Note: the `Continue` inside the `try` exits the `for` iteration; `Segs.Free` still runs via `finally`. All body/header segments are emitted at `Indent`; the pipeline's `ReindentByDepth` (Task 2, Step 5) restores the true `then`/`else` depths.

- [ ] **Step 4: Build Win64 Debug** (via `delphi-build` skill). Expected: `BUILD_EXITCODE=0`.

- [ ] **Step 5: Run the test to verify it passes**

Run: `pwsh -NoProfile -File Test\test_break_control.ps1`
Expected: PASS through the Task 3 section (all of `break_control`).

- [ ] **Step 6: Confirm no regressions** -- `pwsh -NoProfile -File Test\run_tests.ps1`
Expected: `0 failed`.

- [ ] **Step 7: Commit**

```bash
git add YADF.Layout.pas Test/test_break_control.ps1
git commit -m "feat: BreakIfBody -- if/then/else split with glued else-if chains"
```

---

## Task 4: Compile-gate fixture, combined-flags check, docs

Lock the formatted output against the compiler and document the feature.

**Files:**
- Modify: `Test\test_break_control.ps1` (combined-flags + compile check)
- Modify: `CHANGELOG.md`

**Interfaces:** none new.

- [ ] **Step 1: Add a combined-flags + compile assertion** -- append to `Test\test_break_control.ps1` before `Finish`:

```powershell
# ----- Task 4: all three flags together, and the output compiles -----
$all = Fmt '--break-loop --break-with --break-if'
MustMatch $all '(?m)^\s+Dec\(k\);'      'all: loop body split'
MustMatch $all '(?m)^\s+X := 1;'        'all: with body split'
MustMatch $all '(?m)^\s*else\s*$'       'all: if/else split'

# Compile the formatted output of a self-contained, resolvable unit with dcc64,
# reusing the shared compile helper the compile-gate suite uses.
$srcC = Join-Path $env:TEMP 'bctl_compile.pas'
@'
unit bctl_compile;
interface
implementation
procedure Demo;
var
  k, i, Sum: Integer;
begin
  k := 3;
  while k > 0 do Dec(k);
  Sum := 0;
  for i := 0 to 9 do Sum := Sum + i;
  if Sum > 0 then Inc(k) else Dec(k);
end;
end.
'@ | Set-Content $srcC -Encoding ascii
$outC = Join-Path $env:TEMP 'bctl_compiled.pas'
& $exe --ini $ini $srcC --break-loop --break-if --o $outC | Out-Null
Assert-Compiles $outC   # TestLib helper used by test_compile_output.ps1
Remove-Item $srcC,$outC -Force -ErrorAction SilentlyContinue
```

If `TestLib.ps1` exposes the compile helper under a different name than `Assert-Compiles`, match the name used in `Test\test_compile_output.ps1` (read that file's helper call; do not invent a name). If no reusable helper exists, drop this compile block -- the `--check` round-trip in Tasks 2/3 already guards content fidelity, and `test_compile_output.ps1` covers compilation separately.

- [ ] **Step 2: Run the test to verify it passes**

Run: `pwsh -NoProfile -File Test\test_break_control.ps1`
Expected: PASS (all sections).

- [ ] **Step 3: Update `CHANGELOG.md`** -- add under the current in-progress heading (match the existing entry style):

```
- feat: three opt-in body-split options -- BreakLoopBody (for/while), BreakWithBody
  (with..do), BreakIfBody (if/then/else, with glued else-if chains). Each forces a
  single-line control-statement body onto its own indented line; all default off.
  CLI: --break-loop / --break-with / --break-if (+ --no- twins). Surfaced in
  yadf.ini, YADFSetup, and the YADFOT IDE Options page via the option table.
```

- [ ] **Step 4: Full suite green** -- `pwsh -NoProfile -File Test\run_tests.ps1`
Expected: `0 failed`; `break_control` PASS; every prior suite still PASS/SKIP; golden count unchanged.

- [ ] **Step 5: Commit**

```bash
git add Test/test_break_control.ps1 CHANGELOG.md
git commit -m "test: break-control compile gate + combined-flags; docs: CHANGELOG"
```

---

## Self-Review

**1. Spec coverage** (`docs/superpowers/specs/2026-07-22-break-control-bodies-design.md`):
- Three options / names / defaults False -> Task 1. [covered]
- Approach A single pass `BreakControlBodies` -> Tasks 2-3. [covered]
- do-split for/while/with -> Task 2. [covered]
- if/then/else + glued else-if -> Task 3. [covered]
- Non-goals (begin body, nested header, comment line left alone) -> `IsSimpleBody` + `ScanTop` Disq; tested in Task 2 (`begin body untouched`, `nested header untouched`). [covered]
- Pipeline placement after reflow/pack, before alignment, + ReindentByDepth -> Task 2 Step 5. [covered]
- PackShortBodies precedence (split runs later, wins) -> Task 2 Step 5 comment + placement. [covered]
- Idempotency + content-neutral Guard -> idempotency tests Tasks 2-3; Guard passes because only whitespace/CRLF inserted (no tolerance change made). [covered]
- Surfaces auto-wired (INI/YADFSetup/YADFOT) -> Task 1 table entry; INI-template assertion in Task 1. [covered]
- CLI flags + help -> Task 1 Steps 6-7. [covered]
- Tests: fixture, test_break_control.ps1, idempotency, compile gate -> Tasks 2-4. [covered]
- CHANGELOG -> Task 4. [covered]

**2. Placeholder scan:** No TBD/TODO. The one conditional ("if the compile helper has a different name") gives an explicit fallback (match `test_compile_output.ps1` or drop the block) rather than a placeholder.

**3. Type consistency:** `BreakControlBodies(const S: string; const AOpts: TYadfOptions): string` used identically at definition (Task 2) and call site (Task 2 Step 5). Nested `ScanTop` / `IsSimpleBody` / `StartsWordCI` / `OutLine` defined in Task 2 and reused in Task 3 within the same function scope. Option field names `BreakLoopBody`/`BreakWithBody`/`BreakIfBody` consistent across record, defaults, table, CLI, and pipeline guard. Task-3 locals (`Segs`, `isElse`, `Cursor`, `k`, `Ok`, `s2`) added to the same `var` block.

**Open risk flagged for execution:** the exact `TestLib.ps1` compile-helper name (Task 4 Step 1) is unverified; the plan instructs matching `test_compile_output.ps1` or dropping the optional block. The `ReindentByDepth` re-indent of freshly split lines is the load-bearing assumption -- Task 2 Step 8 / Task 3 Step 6 full-suite runs and the idempotency checks are the gate.
