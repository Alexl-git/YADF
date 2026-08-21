# BreakParamsOnePerLine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in YADF formatting option that lays out named routine declarations with one parameter per line, exposed as a checkbox in YADFSetup and YADFOT.

**Architecture:** A new line-level pass, `BreakRoutineParams`, runs immediately after the existing unconditional `JoinRoutineHeaders`. Because that pass has already normalised every routine header onto a single physical line, the new pass is a pure function of that line and is therefore idempotent. Separator placement reuses the existing `UsesCommaLast` option rather than adding a second style knob.

**Tech Stack:** Delphi 13 Florence (RAD Studio 37.0), Object Pascal, Win64. Tests are PowerShell scripts driving the built `YADF.exe`. Compile gating uses `dcc64.exe`.

**Spec:** `docs/superpowers/specs/2026-08-21-break-params-one-per-line-design.md`

## Global Constraints

- **Encoding:** all `.pas` files are strict 7-bit ASCII, no BOM, CRLF line endings. Never introduce Unicode or LF.
- **Naming:** `TMyClass`, `FMyField`, `pMyParam` / `AMyParam` for parameters, matching surrounding code.
- **DocInsight required** on every public declaration: `///` triple-slash XML (`<summary>`, `<param>`, `<returns>`, `<remarks>`). Private helpers only when an invariant is non-obvious.
- **Default is `False`.** The option must not alter output unless explicitly enabled. All 83 existing golden baselines stay byte-identical.
- **Build with the IDE closed** if YADFOT is rebuilt (design-time BPL). Use the `delphi-build` skill recipe: a 3-line wrapper `.bat` (`rsvars` → `cd` → `msbuild`) launched via PowerShell `Start-Process -Wait`, then read the log for `BUILD_EXITCODE=0` and no `[dcc] Error`.
- **Build command:** `msbuild /t:Build /p:Config=Debug /p:Platform=Win64 YADF.dproj`. The test suite requires the exe at `Win64\Debug\EXE\YADF.exe`.
- **Reindex after symbol-changing builds:** `drag-lint index --all --only YADF` (DB: `C:\Projects\YADF\_D-RAG\YADF.sqlite`).
- **Commit granularity:** one commit per task, message prefix `feat:` / `refactor:` / `test:` / `docs:`.

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `YADF.Options.pas` | Settings authority: record, defaults, descriptor table | Modify — 3 insertions |
| `YADF.Layout.pas` | Formatting engine | Modify — hoist 2 helpers, add 4 functions, 1 call site |
| `YadfMain.pas` | CLI surface | Modify — 2 flag branches, 2 help lines |
| `Test\test_break_params.ps1` | Behaviour tests for the new option | Create |
| `CHANGELOG.md` | Release notes | Modify |
| `Demo\Sample.pas` | Option showcase | Modify |

No new units. No UI files — `TYadfOptionsFrame` code-builds its controls from `OptionTable` (`YADF.OptionsFrame.pas:763`), so both hosts pick up the checkbox with zero UI code.

---

### Task 1: Option surface (record, default, table, CLI, help)

Wires the option onto every surface without implementing any behaviour. The flag parses, the INI key generates, the help lists it, and the checkbox appears in both settings dialogs — but output is unchanged.

**Files:**
- Modify: `YADF.Options.pas:79` (record field), `YADF.Options.pas:540` (default), `YADF.Options.pas:759` (table entry)
- Modify: `YadfMain.pas:888` (help), `YadfMain.pas:1305` (flag parsing)
- Test: `Test\test_break_params.ps1` (create)

**Interfaces:**
- Consumes: nothing.
- Produces: `TYadfOptions.BreakParamsOnePerLine: Boolean`, default `False`. CLI flags `--break-params` / `--no-break-params`. INI key `BreakParamsOnePerLine` under `[Format]`.

- [ ] **Step 1: Write the failing test**

Create `Test\test_break_params.ps1`:

```powershell
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

Finish 'break_params'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh -NoProfile -File Test\test_break_params.ps1`
Expected: FAIL on `help lists --break-params`.

- [ ] **Step 3: Add the record field**

`YADF.Options.pas`, in `TYadfOptions`, after `BreakIfBody` (line 79) and before `Delphi10Compat`:

```pascal
    BreakIfBody         : Boolean      ;
    BreakParamsOnePerLine: Boolean     ;
    Delphi10Compat      : Boolean      ;
```

Note: the field name is one character wider than the existing column, so re-align the whole record's colon column or let the next YADF self-format run do it. Do not leave it ragged.

- [ ] **Step 4: Add the default**

`YADF.Options.pas`, in `DefaultOptions`, after line 540:

```pascal
  Result.BreakIfBody         := False;
  Result.BreakParamsOnePerLine:= False;
  Result.Delphi10Compat      := False;
```

- [ ] **Step 5: Add the descriptor-table entry**

`YADF.Options.pas`, in `OptionTable`, immediately after the `BreakCaseLabels` entry (ends line 759), staying inside the `Declarations` group:

```pascal
    MakeOpt('BreakParamsOnePerLine', 'Declarations', 'Break parameters one per line', 'Lay out a routine declaration with one parameter per line ("procedure Go(const A: string; B: Integer);" -> one parameter per line). '
      + 'Fires on named routine declarations with 2 or more parameters; a grouped declaration ("const A, B: string") is split into one name per line, repeating the modifier. '
      + 'Separator placement follows UsesCommaLast. A group carrying an attribute, an interior comment, or an "=" default value is kept whole. '
      + 'Call-site argument lists are never touched. Off by default.', okBool, True, function(const O: TYadfOptions): Variant begin Result:= O.BreakParamsOnePerLine end, procedure(var O: TYadfOptions; const V: Variant) begin O.BreakParamsOnePerLine:= V end),
```

- [ ] **Step 6: Add the CLI flag branches**

`YadfMain.pas`, in `ParseFlags`, after the `--no-break-if` branch (ends line 1305) and before the `--ini` branch:

```pascal
      else if AArgs[i] = '--break-params' then
      begin
        AOpts.BreakParamsOnePerLine:= True;
        Inc(i);
      end
      else if AArgs[i] = '--no-break-params' then
      begin
        AOpts.BreakParamsOnePerLine:= False;
        Inc(i);
      end
```

- [ ] **Step 7: Add the help lines**

`YadfMain.pas`, after line 888 (`--no-break-if`):

```pascal
  WriteStdoutLine(Format('  --break-params        break routine parameters one per line              [params=%s]', [OnOff(AOpts.BreakParamsOnePerLine)]));
  WriteStdoutLine('  --no-break-params     keep the parameter list inline (default)');
```

- [ ] **Step 8: Build**

Per the `delphi-build` skill recipe, Win64 Debug, then confirm `BUILD_EXITCODE=0` and no `[dcc] Error` in the log.

- [ ] **Step 9: Run test to verify it passes**

Run: `pwsh -NoProfile -File Test\test_break_params.ps1`
Expected: PASS, prints `break_params: ...`

- [ ] **Step 10: Verify no regression**

Run: `pwsh -NoProfile -File Test\run_tests.ps1`
Expected: `23 passed, 0 failed` (the new script self-registers via the `test_*.ps1` glob). The 83 goldens must be untouched because the default is `False`.

- [ ] **Step 11: Commit**

```bash
git add YADF.Options.pas YadfMain.pas Test/test_break_params.ps1
git commit -m "feat(options): add BreakParamsOnePerLine option surface"
```

---

### Task 2: Hoist the header-detection helpers to unit scope

Pure refactor, no behaviour change. `LeadWord` and the routine-header test currently live nested inside `JoinRoutineHeaders` (`YADF.Layout.pas:2650` and `:2678`). The new pass needs both. Extract them to unit scope so there is one implementation, not two.

**Files:**
- Modify: `YADF.Layout.pas:2650-2693`
- Test: `Test\test_join_headers.ps1` (existing — this is the regression net)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `function LeadWord(const AText, AWord: string): Boolean;` — True iff `AText` begins with the whole word `AWord`, case-insensitive, with an identifier boundary after.
  - `function IsRoutineHeaderLine(const ALine: string): Boolean;` — True iff `ALine` starts a named routine declaration (`class`/`generic` prefixes tolerated).

- [ ] **Step 1: Confirm the existing net is green before touching anything**

Run: `pwsh -NoProfile -File Test\test_join_headers.ps1`
Expected: PASS. If it fails now, stop — the baseline is broken and this refactor would be blamed for it.

- [ ] **Step 2: Move `LeadWord` to unit scope**

Cut the nested `LeadWord` from inside `JoinRoutineHeaders` and place it at unit scope immediately **before** `function JoinRoutineHeaders`, renaming its parameters to the `A`-prefix convention:

```pascal
/// <summary>True iff AText begins with the whole word AWord (case-insensitive,
/// identifier boundary after).</summary>
/// <param name="AText">Text to test; typically an already-left-trimmed line.</param>
/// <param name="AWord">Keyword to look for at the start of AText.</param>
/// <returns>True on a whole-word prefix match.</returns>
function LeadWord(const AText, AWord: string): Boolean;
begin
  Result:= (Length(AText) >= Length(AWord)) and SameText(Copy(AText, 1, Length(AWord)), AWord) and
  ((Length(AText) = Length(AWord)) or not CharInSet(AText[Length(AWord) + 1], ['a'..'z', 'A'..'Z', '0'..'9', '_']));
end;
```

Leave the call sites inside `JoinRoutineHeaders` unchanged — the signature is compatible.

- [ ] **Step 3: Add the unit-scope routine-header test**

Immediately after `LeadWord`, add. This is the *named-declaration* subset of the existing nested `IsHeaderStart`; it deliberately omits that function's Case B (inline `procedure(` / `function(`), because anonymous headers are out of scope per the spec.

```pascal
/// <summary>True iff ALine begins a NAMED routine declaration -- procedure,
/// function, constructor, destructor or operator, with optional class /
/// generic prefixes.</summary>
/// <param name="ALine">A single physical source line.</param>
/// <returns>True for a named routine header start.</returns>
/// <remarks>Deliberately excludes inline anonymous `procedure(` / `function(`
/// headers: those are expressions, not declarations, and BreakRoutineParams
/// must not touch them.</remarks>
function IsRoutineHeaderLine(const ALine: string): Boolean;
var
  Tr: string;
begin
  Tr:= TrimLeft(ALine);
  if LeadWord(Tr, 'class') then
    Tr:= TrimLeft(Copy(Tr, 6, MaxInt));
  if LeadWord(Tr, 'generic') then
    Tr:= TrimLeft(Copy(Tr, 8, MaxInt));
  Result:= LeadWord(Tr, 'function') or LeadWord(Tr, 'procedure') or LeadWord(Tr, 'constructor')
        or LeadWord(Tr, 'destructor') or LeadWord(Tr, 'operator');
end;
```

- [ ] **Step 4: Build**

Per the `delphi-build` recipe. Expected: clean, zero warnings introduced. A `W1036 variable might not have been initialized` or a duplicate-identifier error here means the nested `LeadWord` was not fully removed.

- [ ] **Step 5: Verify the refactor changed nothing**

Run: `pwsh -NoProfile -File Test\test_join_headers.ps1`
Expected: PASS.

Run: `pwsh -NoProfile -File Test\test_golden_format.ps1`
Expected: PASS, all 83 goldens byte-identical. This is the real proof the extraction was behaviour-neutral.

- [ ] **Step 6: Commit**

```bash
git add YADF.Layout.pas
git commit -m "refactor(layout): hoist LeadWord + IsRoutineHeaderLine to unit scope"
```

---

### Task 3: Top-level scanning helpers

Two small pure functions the splitter is built from. Separated because they carry the trickiest correctness property in the whole feature — the depth/string-aware scan — and a reviewer can meaningfully accept or reject them alone.

**Files:**
- Modify: `YADF.Layout.pas` (insert immediately before `JoinRoutineHeaders`, after `IsRoutineHeaderLine` from Task 2)
- Test: exercised indirectly from Task 4 onward; no standalone test (YADF has no unit-test harness for `Layout` internals — every other pass is tested through the exe).

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `function TopLevelSepPositions(const AText: string; ASep: Char): TArray<Integer>;` — 1-based positions of `ASep` at bracket depth 0, outside quoted strings.
  - `function SplitAtPositions(const AText: string; const APositions: TArray<Integer>): TArray<string>;` — cuts `AText` at those positions, dropping the separator characters, trimming each piece.

- [ ] **Step 1: Add `TopLevelSepPositions`**

```pascal
/// <summary>Returns the 1-based positions of every ASep in AText that sits at
/// bracket depth 0 and outside a quoted string.</summary>
/// <param name="AText">Text to scan.</param>
/// <param name="ASep">Separator character; only ';' ',' ':' and '=' are used.</param>
/// <returns>Ascending positions; empty when none found.</returns>
/// <remarks>Tracks () and [] depth and '' string literals. Deliberately does
/// NOT track &lt;&gt; -- see BreakRoutineParams for why that is safe.</remarks>
function TopLevelSepPositions(const AText: string; ASep: Char): TArray<Integer>;
var
  Depth: Integer      ;
  i    : Integer      ;
  InStr: Boolean      ;
  Res  : TList<Integer>;
begin
  Res:= TList<Integer>.Create;
  try
    Depth:= 0;
    InStr:= False;
    for i:= 1 to Length(AText) do
    begin
      if InStr then
      begin
        if AText[i] = '''' then
          InStr:= False;
        Continue;
      end;
      if AText[i] = '''' then
        InStr:= True
      else if CharInSet(AText[i], ['(', '[']) then
        Inc(Depth)
      else if CharInSet(AText[i], [')', ']']) then
        Dec(Depth)
      else if (AText[i] = ASep) and (Depth = 0) then
        Res.Add(i);
    end;
    Result:= Res.ToArray;
  finally
    Res.Free;
  end; // try
end; // function
```

- [ ] **Step 2: Add `SplitAtPositions`**

```pascal
/// <summary>Cuts AText at the given 1-based positions, dropping the separator
/// character at each position and trimming every piece.</summary>
/// <param name="AText">Text to cut.</param>
/// <param name="APositions">Ascending cut positions, as returned by TopLevelSepPositions.</param>
/// <returns>Length(APositions) + 1 trimmed pieces.</returns>
function SplitAtPositions(const AText: string; const APositions: TArray<Integer>): TArray<string>;
var
  i    : Integer;
  Start: Integer;
begin
  SetLength(Result, Length(APositions) + 1);
  Start:= 1;
  for i:= 0 to High(APositions) do
  begin
    Result[i]:= Trim(Copy(AText, Start, APositions[i] - Start));
    Start    := APositions[i] + 1;
  end;
  Result[High(Result)]:= Trim(Copy(AText, Start, MaxInt));
end; // function
```

- [ ] **Step 3: Build**

Per the `delphi-build` recipe. Expected: clean. Both functions are currently unreferenced — if the compiler emits a hint about that, ignore it; Task 4 consumes them.

- [ ] **Step 4: Commit**

```bash
git add YADF.Layout.pas
git commit -m "feat(layout): add top-level separator scanning helpers"
```

---

### Task 4: The pass — separator-first rendering, no group splitting

Delivers the visible feature for the common case: a `;`-separated parameter list with 2+ items, rendered separator-first (`UsesCommaLast = False`, the default). Grouped names (`const A, B: string`) are still emitted whole — that arrives in Task 5.

**Files:**
- Modify: `YADF.Layout.pas` (add `BreakRoutineParams` before `JoinRoutineHeaders`; add call site at `:5551`)
- Test: `Test\test_break_params.ps1` (extend)

**Interfaces:**
- Consumes: `LeadWord`, `IsRoutineHeaderLine` (Task 2); `TopLevelSepPositions`, `SplitAtPositions` (Task 3).
- Produces: `function BreakRoutineParams(const S: string; const AOpts: TYadfOptions): string;`

- [ ] **Step 1: Write the failing test**

Append to `Test\test_break_params.ps1`, immediately before the `Finish` line:

```powershell
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh -NoProfile -File Test\test_break_params.ps1`
Expected: FAIL on `on: open paren ends the header line` — the flag parses but does nothing yet.

- [ ] **Step 3: Add the pass**

`YADF.Layout.pas`, insert immediately **before** `function JoinRoutineHeaders` (line 2637, after the Task 3 helpers):

```pascal
/// <summary>Lays out named routine declarations with one parameter per line
/// when AOpts.BreakParamsOnePerLine is on and the list has 2+ parameters.
/// Separator placement follows AOpts.UsesCommaLast.</summary>
/// <param name="S">Source text; every routine header already on ONE line.</param>
/// <param name="AOpts">Active options.</param>
/// <returns>S with qualifying parameter lists broken one per line.</returns>
/// <remarks>MUST run after JoinRoutineHeaders, which is unconditional and would
/// otherwise rejoin the split. Because that pass normalises every header onto a
/// single physical line, this one is a pure function of that line and is
/// idempotent. Emits its own final indentation; no ReindentByDepth needed.
/// Content-neutral: inserts only CRLF and spaces.</remarks>
function BreakRoutineParams(const S: string; const AOpts: TYadfOptions): string;
var
  Head  : string        ;
  i     : Integer       ;
  Indent: string        ;
  Items : TArray<string>;
  j     : Integer       ;
  L     : string        ;
  LineWS: string        ;
  Lines : TStringList   ;
  OutVal: TStringBuilder;
  Tail  : string        ;
begin
  if not AOpts.BreakParamsOnePerLine then
    Exit(S);
  Lines := TStringList.Create;
  OutVal:= TStringBuilder.Create;
  try
    Lines.Text:= S;
    for i:= 0 to Lines.Count - 1 do
    begin
      L:= Lines[i];
      if not SplitHeaderParams(L, AOpts, Items, Head, Tail) then
      begin
        OutVal.Append(L).Append(CRLF);
        Continue;
      end;
      LineWS:= Copy(L, 1, Length(L) - Length(TrimLeft(L)));
      Indent:= LineWS + StringOfChar(' ', AOpts.Indent * 2);
      OutVal.Append(Head);
      for j:= 0 to High(Items) do
      begin
        OutVal.Append(CRLF).Append(Indent);
        if AOpts.UsesCommaLast then
        begin
          OutVal.Append(Items[j]);
          if j < High(Items) then
            OutVal.Append(';');
        end // if
        else
        begin
          if j > 0 then
            OutVal.Append('; ');
          OutVal.Append(Items[j]);
        end;
      end; // for
      if AOpts.UsesCommaLast then
        OutVal.Append(Tail).Append(CRLF)
      else
        OutVal.Append(CRLF).Append(Indent).Append(Tail).Append(CRLF);
    end; // for
    Result:= OutVal.ToString;
  finally
    OutVal.Free;
    Lines.Free;
  end; // try
end; // function
```

Note the two rendering shapes: separator-last appends `Tail` directly onto the final item's line; separator-first puts `Tail` alone on a new line at `Indent`.

- [ ] **Step 4: Add the header decomposer**

Insert immediately **before** `BreakRoutineParams`. This is where the trigger and the `//`-comment skip live. `ASplitGroups` is wired in Task 5; for now it returns items split on top-level `;` only.

```pascal
/// <summary>Decomposes a routine header line into its parameter items plus the
/// text before '(' and from ')' onward. Returns False when the line is not a
/// breakable header.</summary>
/// <param name="ALine">One physical source line.</param>
/// <param name="AOpts">Active options.</param>
/// <param name="AItems">Out: the parameter items, one per output line.</param>
/// <param name="AHead">Out: text up to and including the opening '('.</param>
/// <param name="ATail">Out: text from the closing ')' to end of line.</param>
/// <returns>True when ALine should be broken.</returns>
/// <remarks>Refuses: non-headers, headers with no parameter list, unbalanced
/// parens, any header carrying a top-level '//' comment, and lists that yield
/// fewer than 2 items.</remarks>
function SplitHeaderParams(const ALine: string; const AOpts: TYadfOptions;
  out AItems: TArray<string>; out AHead, ATail: string): Boolean;
var
  CloseAt: Integer;
  Inner  : string ;
  OpenAt : Integer;
begin
  Result:= False;
  AItems:= nil;
  AHead := '';
  ATail := '';
  if not IsRoutineHeaderLine(ALine) then
    Exit;
  // A '//' anywhere on the header would swallow every parameter that follows
  // it once the line is broken. Same doctrine as YADF.Layout.pas:5249.
  if Pos('//', ALine) > 0 then
    Exit;
  OpenAt:= Pos('(', ALine);
  if OpenAt = 0 then
    Exit;
  CloseAt:= MatchingCloseParen(ALine, OpenAt);
  if CloseAt <= OpenAt + 1 then
    Exit;
  AHead := Copy(ALine, 1, OpenAt);
  ATail := Copy(ALine, CloseAt, MaxInt);
  Inner := Copy(ALine, OpenAt + 1, CloseAt - OpenAt - 1);
  AItems:= SplitAtPositions(Inner, TopLevelSepPositions(Inner, ';'));
  Result:= Length(AItems) >= 2;
end; // function
```

- [ ] **Step 5: Add `MatchingCloseParen`**

Insert immediately before `SplitHeaderParams`:

```pascal
/// <summary>Returns the 1-based position of the ')' matching the '(' at
/// AOpenAt, or 0 when unbalanced.</summary>
/// <param name="AText">Text to scan.</param>
/// <param name="AOpenAt">1-based position of the opening '('.</param>
/// <returns>Position of the matching ')', or 0.</returns>
function MatchingCloseParen(const AText: string; AOpenAt: Integer): Integer;
var
  Depth: Integer;
  i    : Integer;
  InStr: Boolean;
begin
  Result:= 0;
  Depth := 0;
  InStr := False;
  for i:= AOpenAt to Length(AText) do
  begin
    if InStr then
    begin
      if AText[i] = '''' then
        InStr:= False;
      Continue;
    end;
    if AText[i] = '''' then
      InStr:= True
    else if AText[i] = '(' then
      Inc(Depth)
    else if AText[i] = ')' then
    begin
      Dec(Depth);
      if Depth = 0 then
        Exit(i);
    end;
  end; // for
end; // function
```

- [ ] **Step 6: Add the call site**

`YADF.Layout.pas:5551`. Insert directly after the existing `JoinRoutineHeaders` line:

```pascal
        Result:= JoinRoutineHeaders(Result, AOpts);
        // One parameter per line on named routine declarations. MUST follow
        // JoinRoutineHeaders (which is unconditional and would rejoin the
        // split) and precede Stage-4 alignment, so the split lines take part
        // in AlignTypeColon. Emits its own indentation; no re-indent needed.
        if AOpts.BreakParamsOnePerLine then
          Result:= BreakRoutineParams(Result, AOpts);
```

- [ ] **Step 7: Build, then run the test**

Build per the `delphi-build` recipe, then:
Run: `pwsh -NoProfile -File Test\test_break_params.ps1`
Expected: PASS.

- [ ] **Step 8: Verify no regression**

Run: `pwsh -NoProfile -File Test\run_tests.ps1`
Expected: `23 passed, 0 failed`.

- [ ] **Step 9: Commit**

```bash
git add YADF.Layout.pas Test/test_break_params.ps1
git commit -m "feat(layout): break routine params one per line, separator-first"
```

---

### Task 5: Separator-last rendering and group splitting

Adds the `UsesCommaLast = True` shape and the grouped-name split (`const A, B: string` → one name per line, modifier repeated), including the three no-split fallbacks.

**Files:**
- Modify: `YADF.Layout.pas` (add `SplitParamGroup`; call it from `SplitHeaderParams`)
- Test: `Test\test_break_params.ps1` (extend)

**Interfaces:**
- Consumes: `TopLevelSepPositions`, `SplitAtPositions`, `LeadWord`.
- Produces: `function SplitParamGroup(const AItem: string): TArray<string>;` — returns `[Trim(AItem)]` unchanged when the group must not be split.

- [ ] **Step 1: Write the failing test**

Append to `Test\test_break_params.ps1`, before `Finish`:

```powershell
# ----- Task 5: separator-last mirrors UsesCommaLast -----
$last = FmtDecl 'procedure Go(const A: string; B: Integer);' '--break-params --uses-comma-last'
MustMatch $last '(?m)^\s+const A: string;\s*$' 'comma-last: separator trails the first param'
MustMatch $last '(?m)^\s+B: Integer\);\s*$'    'comma-last: close paren rides the last param'

# ----- Task 5: grouped names split, modifier repeated -----
$grp = FmtDecl 'procedure Copy2(const ASrc, ADest: string; AFlags: Integer);' '--break-params'
MustMatch $grp '(?m)^\s+const ASrc: string\s*$'   'group: first name keeps const'
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh -NoProfile -File Test\test_break_params.ps1`
Expected: FAIL on `comma-last: separator trails the first param` or `group: second name repeats const`.

- [ ] **Step 3: Add the modifier constant**

`YADF.Layout.pas`, in the unit's `const` section (or immediately above `SplitParamGroup` if none is nearby):

```pascal
const
  ParamModifiers: array[0..2] of string = ('const', 'var', 'out');
```

- [ ] **Step 4: Add `SplitParamGroup`**

Insert immediately before `SplitHeaderParams`:

```pascal
/// <summary>Splits one parameter item into one-name-per-line forms, repeating
/// the const/var/out modifier: 'const A, B: string' becomes
/// ['const A: string', 'const B: string'].</summary>
/// <param name="AItem">A single parameter item, already trimmed.</param>
/// <returns>One entry per name, or a single-entry array holding AItem
/// unchanged when the group must not be split.</returns>
/// <remarks>Refuses to split three shapes. (1) A top-level '=' default: the
/// default expression would be duplicated, and a string literal inside it would
/// fail YADF.Guard's exact-sequence check and decline the WHOLE file. (2) An
/// attribute in the name region: duplicating it is not content-neutral. (3) An
/// interior comment: there is no correct line to put it on.
/// Only commas BEFORE the first top-level ':' are considered, so a comma inside
/// the TYPE (TDictionary&lt;string, Integer&gt;) is never a split point -- which is
/// also why no generics-vs-less-than disambiguation is needed here.</remarks>
function SplitParamGroup(const AItem: string): TArray<string>;
var
  Colons: TArray<Integer>;
  Cuts  : TArray<Integer>;
  First : string         ;
  Head  : string         ;
  i     : Integer        ;
  Modif : string         ;
  Names : TArray<string> ;
  Tail  : string         ;
begin
  Result:= [Trim(AItem)];
  if Trim(AItem) = '' then
    Exit;
  // Fallback 3: '=' default value.
  if Length(TopLevelSepPositions(AItem, '=')) > 0 then
    Exit;
  Colons:= TopLevelSepPositions(AItem, ':');
  if Length(Colons) > 0 then
  begin
    Head:= Copy(AItem, 1, Colons[0] - 1);
    Tail:= Copy(AItem, Colons[0], MaxInt);
  end // if
  else
  begin
    Head:= AItem;   // untyped group: `var A, B`
    Tail:= '';
  end;
  // Fallbacks 1 and 2: attribute or comment in the NAME region only.
  if (Pos('[', Head) > 0) or (Pos('{', Head) > 0) or (Pos('(*', Head) > 0) then
    Exit;
  Cuts:= TopLevelSepPositions(Head, ',');
  if Length(Cuts) = 0 then
    Exit;   // single name -- nothing to split
  Names:= SplitAtPositions(Head, Cuts);
  // The modifier rides the FIRST name only; strip it there and repeat it.
  First:= Trim(Names[0]);
  Modif:= '';
  for i:= 0 to High(ParamModifiers) do
    if LeadWord(First, ParamModifiers[i]) then
    begin
      Modif   := ParamModifiers[i] + ' ';
      Names[0]:= Trim(Copy(First, Length(ParamModifiers[i]) + 1, MaxInt));
      Break;
    end;
  SetLength(Result, Length(Names));
  for i:= 0 to High(Names) do
    Result[i]:= Trim(Modif + Trim(Names[i]) + Tail);
end; // function
```

- [ ] **Step 5: Wire it into `SplitHeaderParams`**

Replace the two lines added in Task 4 Step 4:

```pascal
  AItems:= SplitAtPositions(Inner, TopLevelSepPositions(Inner, ';'));
  Result:= Length(AItems) >= 2;
```

with:

```pascal
  Raw:= SplitAtPositions(Inner, TopLevelSepPositions(Inner, ';'));
  Expanded:= TList<string>.Create;
  try
    for i:= 0 to High(Raw) do
      Expanded.AddRange(SplitParamGroup(Raw[i]));
    AItems:= Expanded.ToArray;
  finally
    Expanded.Free;
  end;
  // The 2+ threshold counts parameters AFTER group splitting, so
  // `procedure Swap(var A, B: Integer)` DOES break. Recorded decision.
  Result:= Length(AItems) >= 2;
```

Add `Raw: TArray<string>;`, `Expanded: TList<string>;` and `i: Integer;` to `SplitHeaderParams`'s `var` block.

- [ ] **Step 6: Build, then run the test**

Build per the `delphi-build` recipe, then:
Run: `pwsh -NoProfile -File Test\test_break_params.ps1`
Expected: PASS.

- [ ] **Step 7: Verify no regression**

Run: `pwsh -NoProfile -File Test\run_tests.ps1`
Expected: `23 passed, 0 failed`.

- [ ] **Step 8: Commit**

```bash
git add YADF.Layout.pas Test/test_break_params.ps1
git commit -m "feat(layout): split grouped params, add separator-last rendering"
```

---

### Task 6: Idempotency, round-trip, and the compile gate

Proves the pass emits valid Delphi and is a fixed point. This is the task that catches the failure modes the shape assertions cannot: output that looks right but does not compile, or that changes on a second format.

**Files:**
- Test: `Test\test_break_params.ps1` (extend)

**Interfaces:**
- Consumes: everything from Tasks 1-5.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Write the failing test**

Append to `Test\test_break_params.ps1`, before `Finish`:

```powershell
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

foreach ($f in @('--break-params', '--break-params --uses-comma-last')) {
  $o1 = Join-Path $env:TEMP 'bparm_i1.pas'; $o2 = Join-Path $env:TEMP 'bparm_i2.pas'
  $argv = @($f -split ' ' | Where-Object { $_ -ne '' })
  & $exe --ini $ini $idemSrc @argv --o $o1 | Out-Null
  & $exe --ini $ini $o1      @argv --o $o2 | Out-Null
  if ((Get-FileHash $o1).Hash -ne (Get-FileHash $o2).Hash) { Fail "idempotent: $f" }
  $chk = & $exe --ini $ini --check $o1 2>&1
  if ("$chk" -notmatch 'PASS') { Fail "roundtrip: $f" }
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
```

- [ ] **Step 2: Run test**

Run: `pwsh -NoProfile -File Test\test_break_params.ps1`
Expected: PASS.

If **idempotency** fails, the pass is re-breaking already-broken output — check that `IsRoutineHeaderLine` is not matching a continuation line, and that `JoinRoutineHeaders` really did rejoin the header before this pass ran.

If **round-trip** (`--check`) fails, `FormatPreservesContent` rejected the output. The overwhelmingly likely cause is a duplicated string literal from a defaulted group, meaning the `'='` fallback in `SplitParamGroup` is not firing. Do not relax the guard — fix the fallback.

If **compile** fails, read the `dcc64` error. `E2029`/`E2010` around a split line usually means the modifier was not repeated or `Tail` was lost.

- [ ] **Step 3: Verify the full suite**

Run: `pwsh -NoProfile -File Test\run_tests.ps1`
Expected: `23 passed, 0 failed`.

- [ ] **Step 4: Commit**

```bash
git add Test/test_break_params.ps1
git commit -m "test: idempotency, round-trip and compile gate for --break-params"
```

---

### Task 7: Documentation and showcase

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `Demo\Sample.pas`

**Interfaces:**
- Consumes: the shipped behaviour from Tasks 1-6.
- Produces: nothing.

- [ ] **Step 1: Add the CHANGELOG entry**

At the top of the unreleased section of `CHANGELOG.md`, matching the house style of the `CollapseShortBlocks` entry (line ~573):

```markdown
- **`BreakParamsOnePerLine` (default false; `--break-params`).** Lays out a
  named routine declaration with one parameter per line. Fires on declarations
  with 2 or more parameters; a grouped declaration (`const A, B: string`) is
  split into one name per line with the modifier repeated. Separator placement
  follows `UsesCommaLast`, so a file's uses clauses and parameter lists share
  one style. A group carrying an attribute, an interior comment, or an `=`
  default value is kept whole. Call-site argument lists are never touched.
```

- [ ] **Step 2: Add the showcase block**

`Demo\Sample.pas`, following the `CollapseShortBlocks` marker comment at line 88:

```pascal
// --- BreakParamsOnePerLine ('Break parameters one per line') ---------------
procedure ShowcaseParams(const ASrc, ADest: string; AFlags: Integer; out AErr: string);
begin
end;
```

- [ ] **Step 3: Verify the showcase renders**

Run: `.\Win64\Debug\EXE\YADF.exe Demo\Sample.pas --break-params --stdout`
Expected: `ShowcaseParams` appears with `const ASrc`, `const ADest`, `AFlags` and `out AErr` each on their own line.

- [ ] **Step 4: Reindex**

Run: `C:\Projects\Delphi-RAG-lint\third_party\dll-win64\drag-lint.exe index --all --only YADF`
Expected: clean. The new `Layout` functions become queryable.

- [ ] **Step 5: Commit**

```bash
git add CHANGELOG.md Demo/Sample.pas
git commit -m "docs: document BreakParamsOnePerLine and add the demo showcase"
```

---

## Verification checklist

Before declaring the feature done:

- [ ] `pwsh Test\run_tests.ps1` → `23 passed, 0 failed`
- [ ] `Test\test_golden_format.ps1` → all 83 goldens byte-identical (proves default-off)
- [ ] `Test\test_options.ps1` → passes (proves the descriptor table is coherent)
- [ ] YADFSetup shows the checkbox under **Declarations**, and toggling it changes the live preview
- [ ] YADFOT shows the same checkbox in `Tools > Options` (rebuild the BPL **with the IDE closed**)
- [ ] `.pas` files remain 7-bit ASCII with CRLF
