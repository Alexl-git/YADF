# Join Routine Headers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collapse a routine header that the source split across lines back onto one line, greedy-wrapping at parameter separators only when the joined line exceeds `MaxLen`.

**Architecture:** A new self-contained Stage-3 string pass `JoinRoutineHeaders` in `YADF.Layout.pas`, slotted beside `BreakControlBodies` (after reflow/pack, before alignment). Detection keys off **paren depth** (a split header always breaks inside an unclosed `(`), gated on a leading routine keyword / inline `procedure(`/`function(` so multi-line calls are excluded. It reuses the cross-line `TLineScanState` depth tracker already used by `SplitMultiVarDeclarations`. Overflow wrapping is a dedicated break-after-`;`/`,` greedy wrapper local to the pass (NOT the existing `BreakLineByOperators`, which breaks *before* operators).

**Tech Stack:** Delphi 13 (Studio 37.0), Object Pascal, MSBuild via `rsvars`, PowerShell test harness (`Test\TestLib.ps1`), `dcc64` compile gate, golden-file net.

## Global Constraints

- **Encoding:** all `.pas` edits strict 7-bit ASCII, CRLF line endings, no BOM. DocInsight `///` comment required on the new public function.
- **Always-on, no option:** no `TYadfOptions` field, no INI key, no CLI flag, no GUI entry. The pass runs unconditionally, regardless of `ReflowLines`.
- **Content-neutral / Guard-safe:** only whitespace and line breaks may change; tokens are copied verbatim (so casing is preserved and the Stage-6 `YADF.Guard` net passes).
- **Idempotent:** a second run over the pass's own output must be a byte-for-byte no-op.
- **Build:** use the `delphi-build` skill. Debug Win64 exe at `Win64\Debug\EXE\YADF.exe` is what `Test\run_tests.ps1` exercises — rebuild it after every `.pas` change, IDE closed.
- **Scope OUT:** multi-line CALL argument lists, array/set literals; directives the source split onto their own separate line; the future "Explode" (one-param-per-line) mode.
- **Pipeline insertion point:** `YADF.Layout.pas`, immediately after the `BreakControlBodies` block (currently ends ~line 4904), before the `CollapseBlankLines`/Stage-4 alignment passes.

---

### Task 1: `JoinRoutineHeaders` pass — detection, accumulation, single-line join

Joins a multi-line header onto ONE physical line (even if the result exceeds `MaxLen` — overflow wrapping is Task 2). Excludes calls and safely bails on nested anonymous-method-in-call spans.

**Files:**
- Modify: `YADF.Layout.pas` — add unit-level `function JoinRoutineHeaders` before the main format routine (near `BreakControlBodies`, ~line 2092); add the forward declaration to the unit's `interface` if `BreakControlBodies` has one (mirror it); wire the call into the Stage-3 sequence (~line 4904).
- Test: `Test\test_join_headers.ps1` (new; auto-discovered by `run_tests.ps1`).

**Interfaces:**
- Consumes: `TYadfOptions` (for `AOpts.MaxLen`, `AOpts.Indent`), `TLineScanState` (`Reset`, `ClampDepth`, `Depth`, `InBlockComment`, `BeginLine`, `SkipNonCode`, `StepCode`; events `seEndOfLine`/`seLineComment`/`seCode`), `CRLF`.
- Produces: `function JoinRoutineHeaders(const S: string; const AOpts: TYadfOptions): string;` — the signature Task 2 modifies and the pipeline calls.

- [ ] **Step 1: Write the failing test** (`Test\test_join_headers.ps1`)

```powershell
# Fixture tests for JoinRoutineHeaders: a routine header the source split across
# lines is collapsed onto ONE line (always-on, no flag). Exit 0 = pass, 1 = fail.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestLib.ps1')
$exe = Get-YadfExe
$ini = Get-RepoIni   # pin config: personal %APPDATA% profile must not affect tests
Assert-ToolOrSkip 'join_headers' $exe

# Format a whole unit given as an array of source lines; return formatted text.
function Fmt([string[]]$srcLines) {
  $u = $srcLines -join "`r`n"
  $src = Join-Path $env:TEMP 'jh_in.pas'
  $out = Join-Path $env:TEMP 'jh_out.pas'
  Set-Content -Path $src -Value $u -Encoding ascii
  & $exe --ini $ini $src --o $out | Out-Null
  $t = Get-Content $out -Raw
  Remove-Item $src,$out -Force -ErrorAction SilentlyContinue
  return $t
}

# ----- Motivating case: a 3-line header (fits <= MaxLen) collapses to 1 line -----
$hdr = Fmt @(
  'unit probe;'
  'interface'
  'implementation'
  'function Bar(const A: TBytes;'
  '  B: IThing; C: ISession;'
  '  out D: TCmd): Boolean;'
  'begin'
  '  Result := True;'
  'end;'
  'end.'
)
MustMatch    $hdr '(?m)^function Bar\(const A: TBytes; B: IThing; C: ISession; out D: TCmd\): Boolean;\s*$' 'header joined to one line'
MustNotMatch $hdr '(?m)^\s+B: IThing; C: ISession;\s*$' 'no leftover middle continuation line'

# ----- Interface forward decl + trailing directives: joins params, stops at first ';' -----
$fwd = Fmt @(
  'unit probe;'
  'interface'
  'type'
  '  TFoo = class'
  '    procedure Go(const A: Integer;'
  '      B: Integer); virtual;'
  '  end;'
  'implementation'
  'end.'
)
MustMatch $fwd '(?m)^\s*procedure Go\(const A: Integer; B: Integer\); virtual;\s*$' 'forward decl joined, directive rides along'

# ----- Constructor (Case A leading keyword, not procedure/function) -----
$ctor = Fmt @(
  'unit probe;'
  'interface'
  'implementation'
  'constructor TFoo.Create(const A: string;'
  '  B: Integer);'
  'begin'
  'end;'
  'end.'
)
MustMatch $ctor '(?m)^constructor TFoo\.Create\(const A: string; B: Integer\);\s*$' 'constructor header joined'

# ----- Procedure-type declaration (Case B inline procedure() ) -----
$ptype = Fmt @(
  'unit probe;'
  'interface'
  'type'
  '  TCb = procedure(Sender: TObject;'
  '    const Msg: string) of object;'
  'implementation'
  'end.'
)
MustMatch $ptype '(?m)^\s*TCb = procedure\(Sender: TObject; const Msg: string\) of object;\s*$' 'proc-type decl joined'

# ----- NEGATIVE: a multi-line CALL must survive unchanged -----
$call = Fmt @(
  'unit probe;'
  'interface'
  'implementation'
  'procedure Demo;'
  'begin'
  '  DoStuff(Alpha,'
  '    Beta,'
  '    Gamma);'
  'end;'
  'end.'
)
MustMatch $call '(?m)^\s+Beta,\s*$'  'call arg list left split (line 2)'
MustMatch $call '(?m)^\s+Gamma\);\s*$' 'call arg list left split (line 3)'

Finish 'join_headers'
```

- [ ] **Step 2: Run test to verify it fails**

Build first (see `delphi-build` skill), then:
Run: `pwsh -NoProfile -File Test\test_join_headers.ps1`
Expected: FAIL on the first `MustMatch` — the header is still emitted on 3 lines (no pass yet).

- [ ] **Step 3: Write the pass — detection + accumulation + join (fits case)**

Add before the main format routine in `YADF.Layout.pas` (mirror the placement/style of `BreakControlBodies`). If the unit declares `BreakControlBodies` in its `interface`, add a matching declaration there too.

```pascal
/// <summary>Collapses a routine header the source split across lines back onto
/// one physical line: function/procedure/constructor/destructor/operator
/// declarations (interface forward decls AND implementation headers, nested
/// routines) and procedure-type / anonymous-method headers (inline
/// `procedure(`/`function(`). Detection keys off PAREN DEPTH -- a split header
/// always breaks inside an unclosed '(' -- gated on a leading routine keyword
/// or an inline procedure/function keyword so multi-line CALLS are left alone.
/// Accumulation stops at (and includes) the line that returns paren depth to 0;
/// it never crosses a depth-0 line break, and it aborts (emitting the span
/// unchanged) if a block keyword appears while a paren is still open -- the
/// signature of an anonymous method passed to a call. Content-neutral (tokens
/// copied verbatim, only whitespace/line breaks change) so Guard-safe and
/// casing-preserving. Overflow wrapping is applied by WrapHeaderLine (Task 2).
/// Idempotent. Always-on standard behavior; runs regardless of ReflowLines.</summary>
function JoinRoutineHeaders(const S: string; const AOpts: TYadfOptions): string;
var
  Lines  : TStringList   ;
  Out_   : TStringBuilder;
  St     : TLineScanState;
  i, j   : Integer       ;
  Joined : string        ;
  Aborted: Boolean       ;

  // True iff X begins with the whole word Wd (case-insensitive, ident boundary after).
  function LeadWord(const X, Wd: string): Boolean;
  begin
    Result := (Length(X) >= Length(Wd)) and SameText(Copy(X, 1, Length(Wd)), Wd) and
      ((Length(X) = Length(Wd)) or
       not CharInSet(X[Length(Wd) + 1], ['a'..'z', 'A'..'Z', '0'..'9', '_']));
  end;

  // True iff position p in L starts the whole word Kw (ident boundary before AND
  // after) and the next non-space char after the word is '(' -- an inline routine
  // header keyword like `procedure(` / `function(`.
  function KwParenAt(const L, Kw: string; p: Integer): Boolean;
  var
    q: Integer;
  begin
    Result := False;
    if not SameText(Copy(L, p, Length(Kw)), Kw) then Exit;
    if (p > 1) and CharInSet(L[p - 1], ['a'..'z', 'A'..'Z', '0'..'9', '_']) then Exit;
    q := p + Length(Kw);
    if (q <= Length(L)) and CharInSet(L[q], ['a'..'z', 'A'..'Z', '0'..'9', '_']) then Exit;
    while (q <= Length(L)) and (L[q] = ' ') do Inc(q);
    Result := (q <= Length(L)) and (L[q] = '(');
  end;

  // True iff L, at top level (outside strings/comments), is the first line of a
  // joinable header: a leading routine keyword, or an inline procedure(/function(.
  function IsHeaderStart(const L: string): Boolean;
  var
    Tr         : string ;
    p, n       : Integer;
    inStr, inBlk, inPar: Boolean;
  begin
    Tr := TrimLeft(L);
    if LeadWord(Tr, 'class')   then Tr := TrimLeft(Copy(Tr, 6, MaxInt));
    if LeadWord(Tr, 'generic') then Tr := TrimLeft(Copy(Tr, 8, MaxInt));
    if LeadWord(Tr, 'function') or LeadWord(Tr, 'procedure') or LeadWord(Tr, 'constructor') or
       LeadWord(Tr, 'destructor') or LeadWord(Tr, 'operator') then Exit(True);
    // Case B: inline `procedure(` / `function(` scanned at top level.
    n := Length(L); p := 1; inStr := False; inBlk := False; inPar := False;
    while p <= n do
    begin
      if inStr then begin if L[p] = '''' then begin if (p < n) and (L[p + 1] = '''') then Inc(p) else inStr := False; end; Inc(p); Continue; end;
      if inBlk then begin if L[p] = '}' then inBlk := False; Inc(p); Continue; end;
      if inPar then begin if (L[p] = '*') and (p < n) and (L[p + 1] = ')') then begin inPar := False; Inc(p); end; Inc(p); Continue; end;
      if L[p] = '''' then begin inStr := True; Inc(p); Continue; end;
      if L[p] = '{'  then begin inBlk := True; Inc(p); Continue; end;
      if (L[p] = '(') and (p < n) and (L[p + 1] = '*') then begin inPar := True; Inc(p, 2); Continue; end;
      if (L[p] = '/') and (p < n) and (L[p + 1] = '/') then Break;
      if KwParenAt(L, 'procedure', p) or KwParenAt(L, 'function', p) then Exit(True);
      Inc(p);
    end;
    Result := False;
  end;

  // Advance the shared cross-line scanner St across one physical line L.
  procedure ScanLine(const L: string);
  var
    Col : Integer;
    Done: Boolean;
  begin
    St.BeginLine;
    Col := 1; Done := False;
    while not Done do
    case St.SkipNonCode(L, Col) of
      seEndOfLine  : Done := True;
      seLineComment: Done := True;
      seCode       : St.StepCode(L, Col);
    end;
  end;

  // True iff the trimmed line begins a block/statement keyword that can never
  // appear inside a routine-header parameter list -- the tell-tale that an open
  // paren belongs to a call wrapping an anonymous method, not to a header.
  function StartsBlockKeyword(const L: string): Boolean;
  var
    Tr: string;
  begin
    Tr := TrimLeft(L);
    Result := LeadWord(Tr, 'begin') or LeadWord(Tr, 'asm') or LeadWord(Tr, 'var') or
      LeadWord(Tr, 'const') or LeadWord(Tr, 'type') or LeadWord(Tr, 'label') or
      LeadWord(Tr, 'case') or LeadWord(Tr, 'while') or LeadWord(Tr, 'for') or
      LeadWord(Tr, 'if') or LeadWord(Tr, 'repeat') or LeadWord(Tr, 'with') or
      LeadWord(Tr, 'try');
  end;

begin
  Lines := TStringList.Create;
  try
    Lines.LineBreak := CRLF;
    Lines.Text      := S;
    Out_ := TStringBuilder.Create;
    try
      St.Reset;
      St.ClampDepth := True;
      i := 0;
      while i < Lines.Count do
      begin
        // A joinable header starts only at top level (not mid-paren / mid-comment).
        if (St.Depth = 0) and (not St.InBlockComment) and IsHeaderStart(Lines[i]) then
        begin
          ScanLine(Lines[i]);
          if St.Depth = 0 then
          begin
            // Header already complete on this single physical line -- emit as-is.
            Out_.Append(Lines[i]); Out_.Append(CRLF);
            Inc(i); Continue;
          end;
          // Multi-line header: accumulate until a line returns depth to 0.
          Joined  := TrimRight(Lines[i]);
          Aborted := False;
          j := i + 1;
          while j < Lines.Count do
          begin
            if StartsBlockKeyword(Lines[j]) then begin Aborted := True; Break; end;
            ScanLine(Lines[j]);
            Joined := Joined + ' ' + Trim(Lines[j]);
            if St.Depth = 0 then Break;   // closing line reached (inclusive)
            Inc(j);
          end;
          if Aborted or (j >= Lines.Count) then
          begin
            // Bail: emit the original span verbatim (St already advanced through it).
            for var k := i to j - 1 do begin Out_.Append(Lines[k]); Out_.Append(CRLF); end;
            i := j; Continue;
          end;
          // Task 2 replaces the next line with: Out_.Append(WrapHeaderLine(Joined, AOpts));
          Out_.Append(Joined); Out_.Append(CRLF);
          i := j + 1; Continue;
        end
        else
        begin
          ScanLine(Lines[i]);              // keep cross-line St correct
          Out_.Append(Lines[i]); Out_.Append(CRLF);
          Inc(i);
        end;
      end;
      Result := Out_.ToString;
    finally
      Out_.Free;
    end;
  finally
    Lines.Free;
  end;
end; // function
```

Then wire it into the Stage-3 sequence in the main routine, right after the `BreakControlBodies` block (~line 4904):

```pascal
// Join routine headers the source split across lines back onto one line.
// Always-on standard behavior (no option). Runs after BreakControlBodies (acts
// on the settled line shape) and before Stage-4 alignment. Content-neutral, so
// no re-indent is needed: the header keeps the start line's (already-correct)
// indent and its own continuation indent.
Result := JoinRoutineHeaders(Result, AOpts);
```

- [ ] **Step 4: Run test to verify it passes**

Rebuild the Debug Win64 exe (IDE closed), then:
Run: `pwsh -NoProfile -File Test\test_join_headers.ps1`
Expected: PASS (`join_headers: ...` summary line, exit 0).

- [ ] **Step 5: Commit**

```bash
git add YADF.Layout.pas Test/test_join_headers.ps1
git commit -m "feat: JoinRoutineHeaders pass -- collapse split routine headers onto one line

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Overflow greedy-wrap at `;`/`,`

When the joined header exceeds `MaxLen`, break it AFTER the rightmost top-level `;`/`,` that keeps each line within budget, continuation indented by leading indent + `AOpts.Indent`.

**Files:**
- Modify: `YADF.Layout.pas` — add nested `WrapHeaderLine` to `JoinRoutineHeaders`; change the emit line to call it.
- Test: `Test\test_join_headers.ps1` — add overflow + idempotency assertions.

**Interfaces:**
- Consumes: `AOpts.MaxLen`, `AOpts.Indent`, `TLineScanState`.
- Produces: nested `function WrapHeaderLine(const ALine: string): string;` (closes over `AOpts`, `St`-independent — uses its own fresh scan).

- [ ] **Step 1: Write the failing test** (append to `Test\test_join_headers.ps1`, before `Finish`)

```powershell
# ----- Overflow: a header longer than MaxLen greedy-wraps AFTER ';' -----
# Default MaxLen = 180. Build a header whose one-line form exceeds it.
$long = Fmt @(
  'unit probe;'
  'interface'
  'implementation'
  'function VeryLongRoutineName(const AlphaParameter: TSomeByteArrayType; BetaParameter: IThingInterface;'
  '  GammaParameter: ISessionContext; DeltaParameter: IWhateverInterface; out EpsilonParameter: TCommandID;'
  '  out ZetaParameter: TByteArray): Boolean;'
  'begin'
  '  Result := True;'
  'end;'
  'end.'
)
# Every wrapped line stays within MaxLen (180); continuation lines end at a ';'
# boundary (break AFTER the separator) and are indented deeper than the header.
foreach ($ln in ($long -split "`r`n" | Where-Object { $_ -match 'Parameter' })) {
  if ($ln.Length -gt 180) { Fail "overflow: wrapped line exceeds MaxLen: <$ln>" }
}
MustMatch $long '(?m)Parameter;\s*$' 'overflow: a wrapped line ends at a ; separator'
MustMatch $long '(?m)^function VeryLongRoutineName\('  'overflow: first line still starts the header'

# ----- Idempotency + Guard round-trip over the mixed corpus -----
$idem = Join-Path $env:TEMP 'jh_idem.pas'
@'
unit probe;
interface
type
  TCb = procedure(Sender: TObject;
    const Msg: string) of object;
implementation
function Bar(const A: TBytes;
  B: IThing; C: ISession;
  out D: TCmd): Boolean;
begin
  Result := True;
end;
end.
'@ | Set-Content $idem -Encoding ascii
$o1 = Join-Path $env:TEMP 'jh_i1.pas'; $o2 = Join-Path $env:TEMP 'jh_i2.pas'
& $exe --ini $ini $idem --o $o1 | Out-Null
& $exe --ini $ini $o1   --o $o2 | Out-Null
if ((Get-FileHash $o1).Hash -ne (Get-FileHash $o2).Hash) { Fail 'idempotent: join headers' }
$chk = & $exe --ini $ini --check $o1 2>&1
if ("$chk" -notmatch 'PASS') { Fail 'roundtrip/guard: join headers' }
Remove-Item $idem,$o1,$o2 -Force -ErrorAction SilentlyContinue
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pwsh -NoProfile -File Test\test_join_headers.ps1`
Expected: FAIL on the overflow check — the long header is emitted as a single >180-char line (Task 1 does not wrap).

- [ ] **Step 3: Implement `WrapHeaderLine`**

Add this nested function inside `JoinRoutineHeaders` (alongside `ScanLine`):

```pascal
  // Greedy break of an over-long joined header AFTER top-level ';' / ',' :
  // pick the rightmost separator whose position <= MaxLen, emit head incl. the
  // separator, continue the tail at (leading indent + AOpts.Indent). If no
  // separator fits, leave the line long (better than an invalid mid-token break).
  function WrapHeaderLine(const ALine: string): string;
  var
    Indent, NewIndent, Cur: string;
    W  : TLineScanState  ;
    Col, Best, Depth0Sep : Integer;
    Done: Boolean        ;
    OutB: TStringBuilder ;
  begin
    if Length(ALine) <= AOpts.MaxLen then Exit(ALine);
    Col := 1;
    while (Col <= Length(ALine)) and CharInSet(ALine[Col], [' ', #9]) do Inc(Col);
    Indent    := Copy(ALine, 1, Col - 1);
    NewIndent := Indent + StringOfChar(' ', AOpts.Indent);
    OutB := TStringBuilder.Create;
    try
      Cur := ALine;
      while Length(Cur) > AOpts.MaxLen do
      begin
        // Find the rightmost top-level ';' or ',' at position <= MaxLen.
        Best := 0;
        W.Reset; W.ClampDepth := True; W.BeginLine;
        Col := 1; Done := False;
        while not Done do
        case W.SkipNonCode(Cur, Col) of
          seEndOfLine, seLineComment: Done := True;
          seCode:
            begin
              if (W.Depth = 0) and CharInSet(Cur[Col], [';', ',']) then
              begin
                if Col <= AOpts.MaxLen then Best := Col   // break AFTER this sep
                else Done := True;                        // past budget: stop scanning
              end;
              if not Done then W.StepCode(Cur, Col);
            end;
        end;
        // Don't break at the very last char (nothing to move down) or before indent.
        if (Best <= Length(Indent)) or (Best >= Length(TrimRight(Cur))) then Break;
        OutB.Append(TrimRight(Copy(Cur, 1, Best)));
        OutB.Append(CRLF);
        Cur := NewIndent + TrimLeft(Copy(Cur, Best + 1, MaxInt));
      end;
      OutB.Append(Cur);
      Result := OutB.ToString;
    finally
      OutB.Free;
    end;
  end;
```

Change the Task-1 emit line from `Out_.Append(Joined);` to:

```pascal
          Out_.Append(WrapHeaderLine(Joined));
```

- [ ] **Step 4: Run test to verify it passes**

Rebuild Debug Win64 (IDE closed), then:
Run: `pwsh -NoProfile -File Test\test_join_headers.ps1`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add YADF.Layout.pas Test/test_join_headers.ps1
git commit -m "feat: WrapHeaderLine -- greedy-wrap an over-MaxLen joined header at ;/, separators

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Verification & integration — casing, compile gate, full suite, goldens, CHANGELOG

Prove the pass is valid-Delphi-preserving, casing-faithful, and reconcile the always-on behavior with the existing golden baselines.

**Files:**
- Modify: `Test\test_join_headers.ps1` — casing-fidelity + dcc64 compile-gate blocks.
- Modify: `CHANGELOG.md` — entry under the working version heading.
- Modify (as the suite dictates): re-blessed golden baselines under the golden fixtures dir.

**Interfaces:**
- Consumes: `Get-YadfExe`, `Get-RepoIni`, `MustMatch`, `Fail`, `Finish` from `TestLib.ps1`; `dcc64.exe`.
- Produces: nothing new — closes the feature.

- [ ] **Step 1: Add casing-fidelity + compile-gate blocks** (append before `Finish` in `Test\test_join_headers.ps1`)

```powershell
# ----- Casing fidelity: verbatim token copy respects LowercaseKeywords=False -----
$caseTxt = Fmt @(
  'unit probe;'
  'interface'
  'implementation'
  'FUNCTION Bar(CONST A: TBytes;'
  '  B: IThing): Boolean;'
  'begin'
  '  Result := True;'
  'end;'
  'end.'
) # default ini lowercases keywords; the point here is the JOIN itself never re-cases
# Run again with keyword-lowercasing OFF to prove the join copies source casing verbatim.
$srcC = Join-Path $env:TEMP 'jh_case.pas'
$outC = Join-Path $env:TEMP 'jh_case_out.pas'
@(
  'unit probe;'
  'interface'
  'implementation'
  'FUNCTION Bar(CONST A: TBytes;'
  '  B: IThing): Boolean;'
  'begin'
  '  Result := True;'
  'end;'
  'end.'
) -join "`r`n" | Set-Content $srcC -Encoding ascii
& $exe --ini $ini $srcC --no-lowercase-keywords --o $outC | Out-Null
$c = Get-Content $outC -Raw
MustMatch $c '(?m)^FUNCTION Bar\(CONST A: TBytes; B: IThing\): Boolean;\s*$' 'case: FUNCTION/CONST casing preserved by the join'
Remove-Item $srcC,$outC -Force -ErrorAction SilentlyContinue

# ----- Compile gate: the joined/wrapped output is valid Delphi (dcc64) -----
$dcc = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\dcc64.exe'
if (Test-Path $dcc) {
  $ns   = 'System;System.Win;Winapi;Vcl;Data;Soap;Xml'
  $cdir = Join-Path $env:TEMP ('jh_c_' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $cdir | Out-Null
  $csrc = Join-Path $cdir 'jh_compile.pas'   # file name must equal unit name
  @'
unit jh_compile;
interface
type
  TCb = procedure(Sender: TObject;
    const Msg: string) of object;
  TFoo = class
    procedure Go(const A: Integer;
      B: Integer); virtual;
  end;
implementation
procedure TFoo.Go(const A: Integer;
  B: Integer);
begin
end;
function VeryLongRoutineName(const AlphaParameter: Integer; BetaParameter: Integer;
  GammaParameter: Integer; DeltaParameter: Integer; EpsilonParameter: Integer;
  ZetaParameter: Integer): Boolean;
begin
  Result := True;
end;
end.
'@ | Set-Content $csrc -Encoding ascii
  & $exe $csrc --ini $ini --o $csrc | Out-Null
  & $dcc -Q "-NS$ns" "-N0$cdir" "-E$cdir" $csrc *> $null
  if ($LASTEXITCODE -ne 0) { Fail 'compile: joined/wrapped output must compile with dcc64' }
  Remove-Item $cdir -Recurse -Force -ErrorAction SilentlyContinue
} else {
  Write-Output 'join_headers: (dcc64 not found -- skipping compile check)'
}
```

- [ ] **Step 2: Run the join_headers script; confirm PASS**

Run: `pwsh -NoProfile -File Test\test_join_headers.ps1`
Expected: PASS, including the compile gate line.

- [ ] **Step 3: Run the FULL suite; identify golden drift**

Run: `pwsh -NoProfile -File Test\run_tests.ps1`
Expected: every script PASS **except possibly** `golden_format` and `format_regressions`, which may FAIL where a golden baseline contained a multi-line routine header now joined. Read the diff each reports.

- [ ] **Step 4: Re-bless the affected goldens (only header-join diffs)**

For each golden the suite flags, inspect the diff. It MUST show only routine-header lines collapsing/wrapping — nothing else. If any non-header content changed, STOP: that is a bug in the pass, not a golden to re-bless. Re-bless legitimately-changed baselines using the golden test's documented bless mechanism (see the header comment in `Test\test_golden_format.ps1`), then re-run:

Run: `pwsh -NoProfile -File Test\run_tests.ps1`
Expected: all PASS (skips allowed for missing prebuilt GuardTest/OptionsTest exes).

- [ ] **Step 5: CHANGELOG entry**

Add under the current working version heading in `CHANGELOG.md`:

```markdown
- **Routine headers join onto one line.** A `function`/`procedure`/`constructor`/
  `destructor`/`operator` declaration (interface or implementation) and
  procedure-type declarations that the source split across lines are now
  collapsed onto a single line, greedy-wrapped at parameter separators only when
  the result exceeds MaxLen. Always on; multi-line calls are left untouched.
```

- [ ] **Step 6: Commit**

```bash
git add YADF.Layout.pas Test/test_join_headers.ps1 CHANGELOG.md
git add <re-blessed golden fixtures>
git commit -m "test: join-headers casing + dcc64 gate; re-bless header goldens; CHANGELOG

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- Scope IN (routine headers, interface + impl, nested, proc-type) → Task 1 detection (`IsHeaderStart` Case A + Case B) + tests for each. ✓
- Scope OUT (calls, split directives, explode) → Task 1 negative call test + block-keyword abort; directives stop-at-first-`;` covered by the forward-decl test. ✓
- Paren-depth detection rule → Task 1 accumulation loop (`while ... St.Depth = 0` stop). ✓
- Greedy overflow wrap at separators → Task 2 `WrapHeaderLine`. ✓
- Always-on, no option; runs regardless of ReflowLines → wiring is unconditional, no `TYadfOptions` field added. ✓
- Content-neutral / Guard-safe, idempotent, casing-faithful → Task 2 idempotency+`--check`, Task 3 casing + dcc64. ✓
- Golden blast radius accepted → Task 3 Steps 3–4. ✓

**Placeholder scan:** No TBD/TODO; every code and test step shows complete content. The one forward reference ("Task 2 replaces the emit line") is an explicit, resolved handoff, not a placeholder. ✓

**Type consistency:** `JoinRoutineHeaders(const S: string; const AOpts: TYadfOptions): string` is used identically in the pipeline wiring and both tasks; `WrapHeaderLine`, `ScanLine`, `IsHeaderStart`, `LeadWord`, `KwParenAt`, `StartsBlockKeyword` names are consistent across steps. `TLineScanState` members match those used by `SplitMultiVarDeclarations`. ✓

**Note for the implementer:** the pass code is a faithful reference, but treat the TDD loop as the source of truth — the `TLineScanState` event/member names and `ClampDepth` semantics should be confirmed against the existing `SplitMultiVarDeclarations` usage (`YADF.Layout.pas` ~line 1024–1090) if the compiler disagrees.
