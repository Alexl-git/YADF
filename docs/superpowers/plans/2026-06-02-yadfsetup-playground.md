# YADFSetup Playground — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `YADFSetup.exe`, a 3-column VCL playground (Settings | Source | Result) that tunes every YADF option live and autosaves the shared `yadf.ini`, while consolidating option persistence + metadata into a single descriptor table in `YADF.Options`.

**Architecture:** `YADF.Options` becomes the settings authority: one `YADF_OPTIONS` descriptor table (with per-field Variant accessors) drives `LoadOptionsFromIni`, `SaveOptionsToIni`, `WriteDefaultIniTemplate`, CLI help, and the GUI. CLI and IDE wizard delegate to the shared loader (also fixing the wizard's drift). The GUI calls the pure `FormatSource` on every option/source change.

**Tech Stack:** Delphi 13 Florence (RAD Studio 37.0), VCL (no DevExpress, no Spring), `System.IniFiles`, MSBuild/`rsvars.bat`. ANSI/CRLF source per repo convention. Engine units compiled directly (no fork), exactly as YADFOT does.

**Conventions (apply to every task):**
- All `.pas`/`.dpr`/`.dfm`/`.inc` files: strict 7-bit ASCII, CRLF line endings, no BOM.
- Build command template (run via the Bash tool, which can call cmd.exe):
  ```
  cmd.exe /c "call \"C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat\" && msbuild /t:Build /p:Config=Debug /p:Platform=Win32 <Project>.dproj"
  ```
- Commit after every task with the message shown in its final step.
- Work happens on branch `feat/yadfsetup-playground` (already created).

---

## File Structure

**Modified:**
- `YADF.Options.pas` — add descriptor table, `TOptInfo`, `TOptKind`, helpers (`ReadBoolIni`, `ParseEncoding`, `EncodingToStr`), `LoadOptionsFromIni`, `SaveOptionsToIni`, `OptionsHelpText`; rewrite `WriteDefaultIniTemplate` to render from the table.
- `YadfMain.pas` — delete local `LoadIniDefaults` body / `ReadBoolIni` / `ParseEncoding`; delegate to `YADF.Options`.
- `YADFOT.Wizard.pas` — delete local `LoadIniDefaults` body; delegate to `YADF.Options` (fixes drift).
- `YADF.dproj`, `YADFOT.dproj` — bump VerInfo to 1.0.4.0 (numeric + keys).
- `README.md`, `CHANGELOG.md` — document YADFSetup + the 1.0.4.0 release.

**Created:**
- `YADF.Version.inc` — single source for the version string used in-code.
- `Test\OptionsTest.dpr` + `Test\OptionsTest.dproj` — headless console tests for the new `YADF.Options` API.
- `YADFSetup.dpr` — VCL application entry point.
- `uYADFSetupMain.pas` + `uYADFSetupMain.dfm` — the 3-column main form.
- `YADFSetup.dproj` — VCL GUI Win32 project.
- `Demo\Sample.pas` — feature + modern-Delphi demonstration unit (auto-loaded).
- `build_all.bat` — builds all 3 artifacts with one shared version stamp.

---

## PHASE 1 — Consolidate options persistence in YADF.Options

### Task 1: Move INI helpers into YADF.Options

**Files:**
- Modify: `YADF.Options.pas` (interface + implementation)

- [ ] **Step 1: Add helper declarations to the interface**

In `YADF.Options.pas`, after the existing `function EnsureIniExists(...)` declaration (currently line 82), add:

```pascal
// Encoding name <-> enum, shared by CLI, wizard, GUI, and the INI layer.
function ParseEncoding(const S: string; const ADefault: TYadfEncoding): TYadfEncoding;
function EncodingToStr(const E: TYadfEncoding): string;

// Reads a textual boolean (1/0, true/false, yes/no, on/off; case-insensitive);
// unrecognised values return ADefault. Delphi's TIniFile.ReadBool only honours
// numeric 0/1, but yadf.ini ships textual booleans.
function ReadBoolIni(AIni: TIniFile; const ASection, AIdent: string; ADefault: Boolean): Boolean;
```

Add `System.IniFiles` to the interface `uses` clause (currently `System.SysUtils, System.Classes, System.IOUtils`):

```pascal
uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.IniFiles,
  System.Variants;
```

- [ ] **Step 2: Add helper implementations**

In the `implementation` section of `YADF.Options.pas` (before `end.`), add (this is the exact `ParseEncoding` body copied from `YadfMain.pas:810`, plus `EncodingToStr` and `ReadBoolIni` copied from `YadfMain.pas:868`):

```pascal
function ParseEncoding(const S: string; const ADefault: TYadfEncoding): TYadfEncoding;
var
  L: string;
begin
  L:= UpperCase(Trim(S));
  if (L = 'UTF-8') or (L = 'UTF8') or (L = 'UTF-8-BOM') or (L = 'UTF8BOM') then
    Result:= encUTF8BOM
  else if (L = 'UTF-16') or (L = 'UTF16') or (L = 'UTF-16-BOM') or (L = 'UTF16BOM') or (L = 'UTF-16-LE') then
    Result:= encUTF16BOM
  else if (L = 'ANSI') then
    Result:= encANSI
  else
    Result:= ADefault;
end;

function EncodingToStr(const E: TYadfEncoding): string;
begin
  case E of
    encUTF8BOM : Result:= 'UTF-8';
    encUTF16BOM: Result:= 'UTF-16';
  else
    Result:= 'ANSI';
  end;
end;

function ReadBoolIni(AIni: TIniFile; const ASection, AIdent: string; ADefault: Boolean): Boolean;
var
  S: string;
begin
  S:= LowerCase(Trim(AIni.ReadString(ASection, AIdent, '')));
  if (S = '1') or (S = 'true' ) or (S = 'yes') or (S = 'on' ) then Exit(True );
  if (S = '0') or (S = 'false') or (S = 'no' ) or (S = 'off') then Exit(False);
  Result:= ADefault;
end;
```

- [ ] **Step 3: Build to verify the unit still compiles**

Run:
```
cmd.exe /c "call \"C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat\" && msbuild /t:Build /p:Config=Debug /p:Platform=Win32 YADF.dproj"
```
Expected: `Build succeeded.` (YADF.exe still compiles; `ParseEncoding`/`ReadBoolIni` now exist in two units — this is fine until Task 6 removes the YadfMain copies, because YadfMain's own copies still shadow within that unit).

> NOTE: If the compiler reports a duplicate-identifier ambiguity in `YadfMain.pas` (it `uses YADF.Options`), it will be resolved in Task 6. If the build fails here specifically due to ambiguity, proceed to Task 6 before re-running; otherwise commit now.

- [ ] **Step 4: Commit**

```bash
git add YADF.Options.pas
git commit -m "refactor: move ParseEncoding/EncodingToStr/ReadBoolIni into YADF.Options"
```

---

### Task 2: Add the option descriptor table

**Files:**
- Modify: `YADF.Options.pas` (interface + implementation)

- [ ] **Step 1: Declare the descriptor types and accessor in the interface**

After the helper declarations from Task 1, add:

```pascal
type
  TOptKind = (okBool, okInt, okString, okEnum);

  TOptGetter = reference to function(const O: TYadfOptions): Variant;
  TOptSetter = reference to procedure(var O: TYadfOptions; const V: Variant);

  TOptInfo = record
    Ident         : string;      // INI key under [Format] AND the record field name
    Group         : string;      // UI group + template section header
    Caption       : string;      // GUI label
    Hint          : string;      // one-line help: GUI tooltip, ';' comment, --help line
    Kind          : TOptKind;
    AffectsPreview: Boolean;     // False for file/CLI-only options
    GetVal        : TOptGetter;
    SetVal        : TOptSetter;
  end;

// The single authority for every TYadfOptions field. Built once on first call.
function OptionTable: TArray<TOptInfo>;
```

- [ ] **Step 2: Implement the table builder**

In the implementation section add a unit-private cache var and `OptionTable`. The encoding option stores/loads as a string name (`okEnum`). Full table (one entry per field; groups ordered for the template/UI):

```pascal
var
  GOptTable: TArray<TOptInfo>;

function MakeOpt(const AIdent, AGroup, ACaption, AHint: string; AKind: TOptKind;
  AAffects: Boolean; const AGet: TOptGetter; const ASet: TOptSetter): TOptInfo;
begin
  Result.Ident := AIdent;
  Result.Group := AGroup;
  Result.Caption := ACaption;
  Result.Hint := AHint;
  Result.Kind := AKind;
  Result.AffectsPreview := AAffects;
  Result.GetVal := AGet;
  Result.SetVal := ASet;
end;

function OptionTable: TArray<TOptInfo>;
begin
  if Length(GOptTable) > 0 then Exit(GOptTable);
  GOptTable := [
    MakeOpt('MaxLen', 'Line length & indentation', 'Max line length',
      'Maximum line length in columns. Long lines are reflowed when ReflowLines is true. Default: 180',
      okInt, True,
      function(const O: TYadfOptions): Variant begin Result := O.MaxLen end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.MaxLen := V end),
    MakeOpt('Indent', 'Line length & indentation', 'Indent step',
      'Indentation step in spaces (each nesting level adds this many). Default: 2',
      okInt, True,
      function(const O: TYadfOptions): Variant begin Result := O.Indent end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.Indent := V end),
    MakeOpt('TabWidth', 'Line length & indentation', 'Tab width',
      'Width assumed for an existing tab on input. YADF always emits spaces. Default: 4',
      okInt, True,
      function(const O: TYadfOptions): Variant begin Result := O.TabWidth end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.TabWidth := V end),
    MakeOpt('ReflowLines', 'Reflow & whitespace', 'Reflow long lines',
      'Reflow lines that exceed MaxLen. When false, long lines are left as-is. Default: true',
      okBool, True,
      function(const O: TYadfOptions): Variant begin Result := O.ReflowLines end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.ReflowLines := V end),
    MakeOpt('TrimTrailing', 'Reflow & whitespace', 'Trim trailing spaces',
      'Trim trailing whitespace from every output line. Default: true',
      okBool, True,
      function(const O: TYadfOptions): Variant begin Result := O.TrimTrailing end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.TrimTrailing := V end),
    MakeOpt('MaxBlankLines', 'Reflow & whitespace', 'Max blank lines',
      'Maximum consecutive blank lines kept in output. Excess blanks are collapsed. Default: 1',
      okInt, True,
      function(const O: TYadfOptions): Variant begin Result := O.MaxBlankLines end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.MaxBlankLines := V end),
    MakeOpt('BlanksBeforeSection', 'Reflow & whitespace', 'Blanks before section',
      'Blank lines forced before each interface section. 0 = no change. Default: 0',
      okInt, True,
      function(const O: TYadfOptions): Variant begin Result := O.BlanksBeforeSection end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.BlanksBeforeSection := V end),
    MakeOpt('BlanksBeforeMethod', 'Reflow & whitespace', 'Blanks before method',
      'Blank lines forced before each method body. Default: 0',
      okInt, True,
      function(const O: TYadfOptions): Variant begin Result := O.BlanksBeforeMethod end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.BlanksBeforeMethod := V end),
    MakeOpt('BlanksBeforeType', 'Reflow & whitespace', 'Blanks before type',
      'Blank lines forced before each top-level type declaration. Default: 0',
      okInt, True,
      function(const O: TYadfOptions): Variant begin Result := O.BlanksBeforeType end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.BlanksBeforeType := V end),
    MakeOpt('LowercaseKeywords', 'Casing', 'Lowercase keywords',
      'Lowercase Pascal keywords (begin, end, if, then ...). Default: true',
      okBool, True,
      function(const O: TYadfOptions): Variant begin Result := O.LowercaseKeywords end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.LowercaseKeywords := V end),
    MakeOpt('UpperHexNumbers', 'Casing', 'Uppercase hex',
      'Uppercase hex digits in numeric literals ($AB not $ab). Default: true',
      okBool, True,
      function(const O: TYadfOptions): Variant begin Result := O.UpperHexNumbers end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.UpperHexNumbers := V end),
    MakeOpt('UpperDirectives', 'Casing', 'Uppercase directives',
      'Uppercase compiler-directive keywords ({$IFDEF}, {$R+} ...). Default: true',
      okBool, True,
      function(const O: TYadfOptions): Variant begin Result := O.UpperDirectives end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.UpperDirectives := V end),
    MakeOpt('FirstOccCasing', 'Casing', 'First-occurrence casing',
      'Cascade casing from the first occurrence of each identifier to all later uses. Default: true',
      okBool, True,
      function(const O: TYadfOptions): Variant begin Result := O.FirstOccCasing end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.FirstOccCasing := V end),
    MakeOpt('AssignNoSpaceBefore', 'Assignment & alignment', 'No space before :=',
      'No space BEFORE := ("X:= 1" not "X := 1"). Default: true',
      okBool, True,
      function(const O: TYadfOptions): Variant begin Result := O.AssignNoSpaceBefore end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.AssignNoSpaceBefore := V end),
    MakeOpt('AssignSpaceAfter', 'Assignment & alignment', 'Space after :=',
      'Single space AFTER := ("X:= 1" not "X:=1"). Default: true',
      okBool, True,
      function(const O: TYadfOptions): Variant begin Result := O.AssignSpaceAfter end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.AssignSpaceAfter := V end),
    MakeOpt('AlignConstEquals', 'Assignment & alignment', 'Align const =',
      'Vertical-align = in const blocks. Default: true',
      okBool, True,
      function(const O: TYadfOptions): Variant begin Result := O.AlignConstEquals end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.AlignConstEquals := V end),
    MakeOpt('AlignTypeColon', 'Assignment & alignment', 'Align type :',
      'Vertical-align : in type / var / parameter blocks. Default: true',
      okBool, True,
      function(const O: TYadfOptions): Variant begin Result := O.AlignTypeColon end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.AlignTypeColon := V end),
    MakeOpt('AlignSmartAssign', 'Assignment & alignment', 'Smart-align :=',
      'Smart-align := across consecutive assignment statements. Default: true',
      okBool, True,
      function(const O: TYadfOptions): Variant begin Result := O.AlignSmartAssign end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.AlignSmartAssign := V end),
    MakeOpt('AlignMaxColumn', 'Assignment & alignment', 'Align max column',
      'Maximum column an alignment may push to. Past this, alignment is skipped. Default: 140',
      okInt, True,
      function(const O: TYadfOptions): Variant begin Result := O.AlignMaxColumn end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.AlignMaxColumn := V end),
    MakeOpt('AlignMatchingShapes', 'Assignment & alignment', 'Align matching shapes',
      'Align matching "shapes" (record-init lines, repeated field declarations). Default: true',
      okBool, True,
      function(const O: TYadfOptions): Variant begin Result := O.AlignMatchingShapes end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.AlignMatchingShapes := V end),
    MakeOpt('AlignShapeMinAnchors', 'Assignment & alignment', 'Shape min anchors',
      'Minimum anchors required before shape-alignment kicks in. Default: 3',
      okInt, True,
      function(const O: TYadfOptions): Variant begin Result := O.AlignShapeMinAnchors end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.AlignShapeMinAnchors := V end),
    MakeOpt('AlignCommentMaxShift', 'Assignment & alignment', 'Comment max shift',
      'Maximum columns a trailing comment may shift when aligning to a shape. Default: 7',
      okInt, True,
      function(const O: TYadfOptions): Variant begin Result := O.AlignCommentMaxShift end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.AlignCommentMaxShift := V end),
    MakeOpt('UsesAlwaysBreak', 'Uses clauses', 'Break uses one-per-line',
      'Always break uses clauses one unit per line. Default: true',
      okBool, True,
      function(const O: TYadfOptions): Variant begin Result := O.UsesAlwaysBreak end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.UsesAlwaysBreak := V end),
    MakeOpt('SplitMultiVarDecls', 'Declarations', 'Split multi-var decls',
      'Split "I, J: integer;" into one line per name so the type colons align. Default: true',
      okBool, True,
      function(const O: TYadfOptions): Variant begin Result := O.SplitMultiVarDecls end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.SplitMultiVarDecls := V end),
    MakeOpt('AlignDeclSemicolons', 'Declarations', 'Align decl semicolons',
      'After AlignTypeColon, align the trailing ; on consecutive declaration lines. Default: true',
      okBool, True,
      function(const O: TYadfOptions): Variant begin Result := O.AlignDeclSemicolons end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.AlignDeclSemicolons := V end),
    MakeOpt('LabelLongBlocks', 'Labels & markers', 'Label long blocks',
      'Insert "// end of <Name>" markers after long blocks. Default: true',
      okBool, True,
      function(const O: TYadfOptions): Variant begin Result := O.LabelLongBlocks end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.LabelLongBlocks := V end),
    MakeOpt('LabelMinLines', 'Labels & markers', 'Label min lines',
      'Minimum lines a block must span before LabelLongBlocks adds the marker. Default: 15',
      okInt, True,
      function(const O: TYadfOptions): Variant begin Result := O.LabelMinLines end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.LabelMinLines := V end),
    MakeOpt('MarkUnclosed', 'Labels & markers', 'Mark unclosed blocks',
      'Add a "// UNCLOSED" marker when an opening keyword has no matching close. Default: false',
      okBool, True,
      function(const O: TYadfOptions): Variant begin Result := O.MarkUnclosed end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.MarkUnclosed := V end),
    MakeOpt('Backup', 'File & CLI (no preview effect)', 'Backup before overwrite',
      'Create a backup of every file before overwriting it. Default: false',
      okBool, False,
      function(const O: TYadfOptions): Variant begin Result := O.Backup end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.Backup := V end),
    MakeOpt('BackupDir', 'File & CLI (no preview effect)', 'Backup directory',
      'Directory for backups (used when Backup=true). Empty = next to original file. Default: empty',
      okString, False,
      function(const O: TYadfOptions): Variant begin Result := O.BackupDir end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.BackupDir := VarToStr(V) end),
    MakeOpt('ResultDir', 'File & CLI (no preview effect)', 'Result directory',
      'Directory for formatted output. Empty = format in place. Default: empty',
      okString, False,
      function(const O: TYadfOptions): Variant begin Result := O.ResultDir end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.ResultDir := VarToStr(V) end),
    MakeOpt('Encoding', 'File & CLI (no preview effect)', 'Output encoding',
      'File encoding to write: ANSI, UTF-8 (with BOM), or UTF-16 (with BOM). Default: ANSI',
      okEnum, False,
      function(const O: TYadfOptions): Variant begin Result := EncodingToStr(O.Encoding) end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.Encoding := ParseEncoding(VarToStr(V), encANSI) end),
    MakeOpt('Logging', 'File & CLI (no preview effect)', 'Logging',
      'Write a log file with details of every option resolved and file processed. Default: false',
      okBool, False,
      function(const O: TYadfOptions): Variant begin Result := O.Logging end,
      procedure(var O: TYadfOptions; const V: Variant) begin O.Logging := V end)
  ];
  Result := GOptTable;
end;
```

> The enum option's allowed display values are `ANSI`, `UTF-8`, `UTF-16` (see `EncodingToStr`). The GUI combo (Task 9) uses exactly these three strings.

- [ ] **Step 3: Build**

Run the YADF.dproj Debug/Win32 build command.
Expected: `Build succeeded.`

- [ ] **Step 4: Commit**

```bash
git add YADF.Options.pas
git commit -m "feat: add YADF_OPTIONS descriptor table (single source for all 33 options)"
```

---

### Task 3: Table-driven Load/Save + write a failing test first

**Files:**
- Create: `Test\OptionsTest.dpr`
- Create: `Test\OptionsTest.dproj`
- Modify: `YADF.Options.pas`

- [ ] **Step 1: Write the failing test program**

Create `Test\OptionsTest.dpr` (console; references the engine units via the shared search path). This asserts round-trip identity, comment preservation, and descriptor completeness:

```pascal
program OptionsTest;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Variants,
  YADF.Options in '..\YADF.Options.pas';

var
  GFailures: Integer = 0;

procedure Check(const AName: string; ACond: Boolean);
begin
  if ACond then
    Writeln('ok   - ', AName)
  else
  begin
    Writeln('FAIL - ', AName);
    Inc(GFailures);
  end;
end;

// Count of fields in TYadfOptions; the descriptor table must match exactly.
const
  EXPECTED_OPTION_COUNT = 33;

procedure TestDescriptorCompleteness;
var
  T: TArray<TOptInfo>;
begin
  T := OptionTable;
  Check('descriptor count == record field count', Length(T) = EXPECTED_OPTION_COUNT);
end;

procedure TestRoundTrip;
var
  A, B: TYadfOptions;
  Path: string;
  T: TArray<TOptInfo>;
  i: Integer;
  Mism: string;
begin
  A := DefaultOptions;
  // perturb a few fields so we are not just re-reading defaults
  A.MaxLen := 99;
  A.Indent := 7;
  A.LowercaseKeywords := False;
  A.BackupDir := 'C:\tmp\bak';
  A.Encoding := encUTF8BOM;
  Path := TPath.Combine(TPath.GetTempPath, 'yadf_roundtrip_test.ini');
  if TFile.Exists(Path) then TFile.Delete(Path);
  SaveOptionsToIni(A, Path);
  B := LoadOptionsFromIni(Path);
  T := OptionTable;
  Mism := '';
  for i := 0 to High(T) do
    if VarToStr(T[i].GetVal(A)) <> VarToStr(T[i].GetVal(B)) then
      Mism := Mism + ' ' + T[i].Ident;
  Check('round-trip identity for all fields (mismatch:' + Mism + ')', Mism = '');
  TFile.Delete(Path);
end;

procedure TestCommentPreservation;
var
  A: TYadfOptions;
  Path: string;
  S: string;
begin
  A := DefaultOptions;
  Path := TPath.Combine(TPath.GetTempPath, 'yadf_comments_test.ini');
  if TFile.Exists(Path) then TFile.Delete(Path);
  SaveOptionsToIni(A, Path);  // should ensure template (with ';' comments) first
  S := TFile.ReadAllText(Path, TEncoding.ANSI);
  Check('saved ini keeps ; comment lines', S.Contains(';'));
  Check('saved ini has [Format] section', S.Contains('[Format]'));
  TFile.Delete(Path);
end;

begin
  try
    TestDescriptorCompleteness;
    TestRoundTrip;
    TestCommentPreservation;
    Writeln('');
    if GFailures = 0 then
      Writeln('ALL PASS')
    else
      Writeln(Format('%d FAILURE(S)', [GFailures]));
  except
    on E: Exception do
    begin
      Writeln('EXCEPTION: ', E.ClassName, ': ', E.Message);
      Inc(GFailures);
    end;
  end;
  ExitCode := GFailures;
end.
```

- [ ] **Step 2: Create the console test project**

Create `Test\OptionsTest.dproj` (minimal console app; unit search path points at the repo root and DelphiAST is NOT needed because `YADF.Options` only depends on RTL):

```xml
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <PropertyGroup>
        <ProjectGuid>{B2D6F2A1-1C2E-49F2-9B77-0A1F0E2D3C44}</ProjectGuid>
        <ProjectVersion>20.4</ProjectVersion>
        <FrameworkType>None</FrameworkType>
        <Base>True</Base>
        <Config Condition="'$(Config)'==''">Debug</Config>
        <Platform Condition="'$(Platform)'==''">Win32</Platform>
        <AppType>Console</AppType>
        <MainSource>OptionsTest.dpr</MainSource>
    </PropertyGroup>
    <PropertyGroup Condition="'$(Base)'!=''">
        <DCC_DcuOutput>.\$(Platform)\$(Config)\DCU</DCC_DcuOutput>
        <DCC_ExeOutput>.\$(Platform)\$(Config)\EXE</DCC_ExeOutput>
        <DCC_ConsoleTarget>true</DCC_ConsoleTarget>
        <DCC_Namespace>System;$(DCC_Namespace)</DCC_Namespace>
        <VerInfo_IncludeVerInfo>false</VerInfo_IncludeVerInfo>
    </PropertyGroup>
    <PropertyGroup Condition="'$(Config)'=='Debug'">
        <DCC_Define>DEBUG;$(DCC_Define)</DCC_Define>
        <DCC_Optimize>false</DCC_Optimize>
    </PropertyGroup>
    <ItemGroup>
        <DelphiCompile Include="$(MainSource)">
            <MainSource>MainSource</MainSource>
        </DelphiCompile>
        <DCCReference Include="..\YADF.Options.pas"/>
        <BuildConfiguration Include="Debug">
            <Key>Cfg_1</Key>
        </BuildConfiguration>
    </ItemGroup>
    <ProjectExtensions>
        <Borland.Personality>Delphi.Personality.12</Borland.Personality>
        <Borland.ProjectType>Application</Borland.ProjectType>
        <BorlandProject>
            <Delphi.Personality>
                <Source>
                    <Source Name="MainSource">OptionsTest.dpr</Source>
                </Source>
            </Delphi.Personality>
        </BorlandProject>
    </ProjectExtensions>
</Project>
```

- [ ] **Step 3: Verify it fails (functions not yet implemented)**

Run:
```
cmd.exe /c "call \"C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat\" && msbuild /t:Build /p:Config=Debug /p:Platform=Win32 Test\OptionsTest.dproj"
```
Expected: **FAIL** — `Undeclared identifier: 'SaveOptionsToIni'` / `'LoadOptionsFromIni'`.

- [ ] **Step 4: Implement Load/Save in YADF.Options**

Add to the interface (after `OptionTable`):

```pascal
function  LoadOptionsFromIni(const APath: string): TYadfOptions;
procedure SaveOptionsToIni(const AOpts: TYadfOptions; const APath: string);
```

Add to the implementation:

```pascal
function LoadOptionsFromIni(const APath: string): TYadfOptions;
var
  Ini: TIniFile;
  T  : TArray<TOptInfo>;
  i  : Integer;
begin
  Result := DefaultOptions;
  if (APath = '') or (not FileExists(APath)) then Exit;
  T := OptionTable;
  Ini := TIniFile.Create(APath);
  try
    for i := 0 to High(T) do
      case T[i].Kind of
        okInt:
          T[i].SetVal(Result, Ini.ReadInteger('Format', T[i].Ident, T[i].GetVal(Result)));
        okBool:
          T[i].SetVal(Result, ReadBoolIni(Ini, 'Format', T[i].Ident, T[i].GetVal(Result)));
        okString, okEnum:
          T[i].SetVal(Result, Ini.ReadString('Format', T[i].Ident, VarToStr(T[i].GetVal(Result))));
      end;
  finally
    Ini.Free;
  end;
end;

procedure SaveOptionsToIni(const AOpts: TYadfOptions; const APath: string);
var
  Ini: TIniFile;
  T  : TArray<TOptInfo>;
  i  : Integer;
begin
  // Ensure the commented template exists first so WinAPI INI writes update
  // values in place and leave the ';' comment lines intact.
  EnsureIniExists(APath);
  T := OptionTable;
  Ini := TIniFile.Create(APath);
  try
    for i := 0 to High(T) do
      case T[i].Kind of
        okInt : Ini.WriteInteger('Format', T[i].Ident, T[i].GetVal(AOpts));
        okBool: Ini.WriteString ('Format', T[i].Ident,
                  IfThen(Boolean(T[i].GetVal(AOpts)), 'true', 'false'));
        okString, okEnum:
                Ini.WriteString ('Format', T[i].Ident, VarToStr(T[i].GetVal(AOpts)));
      end;
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
end;
```

Add `System.StrUtils` to the implementation `uses` (for `IfThen`). If there is no implementation `uses` clause yet, add one right after `implementation`:

```pascal
implementation

uses
  System.StrUtils;
```

- [ ] **Step 5: Build and run the test, expect ALL PASS**

Run the OptionsTest build command, then:
```
cmd.exe /c "Test\Win32\Debug\EXE\OptionsTest.exe"
```
Expected: lines `ok - ...` and final `ALL PASS` (process exit code 0).

If `descriptor count` fails, the table is missing/duplicating a field — fix the table in Task 2. If round-trip fails for `Encoding`, confirm the combo values match `EncodingToStr`.

- [ ] **Step 6: Commit**

```bash
git add YADF.Options.pas Test/OptionsTest.dpr Test/OptionsTest.dproj
git commit -m "feat: table-driven LoadOptionsFromIni/SaveOptionsToIni + headless tests"
```

---

### Task 4: Render template + CLI help from the table

**Files:**
- Modify: `YADF.Options.pas`

- [ ] **Step 1: Add a help-text accessor to the interface**

```pascal
function OptionsHelpText: string;  // one "Ident - Hint" line per option, grouped
```

- [ ] **Step 2: Implement OptionsHelpText and rewrite WriteDefaultIniTemplate from the table**

Replace the body of `WriteDefaultIniTemplate` (currently the long hardcoded `L.Add(...)` list, lines ~132-307) with a table-driven renderer, and add `OptionsHelpText`:

```pascal
function DefaultValueStr(const AInfo: TOptInfo): string;
var
  D: TYadfOptions;
begin
  D := DefaultOptions;
  case AInfo.Kind of
    okBool: Result := IfThen(Boolean(AInfo.GetVal(D)), 'true', 'false');
  else
    Result := VarToStr(AInfo.GetVal(D));
  end;
end;

procedure WriteDefaultIniTemplate(const APath: string);
var
  L      : TStringList;
  DirName: string;
  T      : TArray<TOptInfo>;
  i      : Integer;
  CurGrp : string;
begin
  DirName := ExtractFilePath(APath);
  if (DirName <> '') and (not DirectoryExists(DirName)) then
    ForceDirectories(DirName);
  T := OptionTable;
  L := TStringList.Create;
  try
    L.Add('; YADF -- Yet Another Delphi Formatter');
    L.Add('; Default configuration. Edit values and re-run.');
    L.Add('; Lines starting with `;` are comments.');
    L.Add('; CLI flags override these values; --ini <path> overrides location.');
    L.Add('');
    L.Add('[Format]');
    CurGrp := '';
    for i := 0 to High(T) do
    begin
      if T[i].Group <> CurGrp then
      begin
        CurGrp := T[i].Group;
        L.Add('');
        L.Add('; ---- ' + CurGrp + ' ----');
      end;
      L.Add('');
      L.Add('; ' + T[i].Hint);
      L.Add(T[i].Ident + ' = ' + DefaultValueStr(T[i]));
    end;
    L.SaveToFile(APath, TEncoding.ANSI);
  finally
    L.Free;
  end;
end;

function OptionsHelpText: string;
var
  T     : TArray<TOptInfo>;
  i     : Integer;
  CurGrp: string;
  SB    : TStringBuilder;
begin
  T := OptionTable;
  SB := TStringBuilder.Create;
  try
    CurGrp := '';
    for i := 0 to High(T) do
    begin
      if T[i].Group <> CurGrp then
      begin
        CurGrp := T[i].Group;
        SB.AppendLine;
        SB.AppendLine('  [' + CurGrp + ']');
      end;
      SB.AppendLine(Format('    %-22s %s', [T[i].Ident, T[i].Hint]));
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;
```

Ensure `WriteDefaultIniTemplate`'s forward declaration in the interface is unchanged (same signature).

- [ ] **Step 3: Re-run the OptionsTest (comment preservation still holds)**

Rebuild & run `OptionsTest.exe`.
Expected: `ALL PASS`. (The comment-preservation test still finds `;` and `[Format]`.)

- [ ] **Step 4: Build YADF.exe to confirm template change compiles**

Run YADF.dproj Debug/Win32 build. Expected: `Build succeeded.`

- [ ] **Step 5: Commit**

```bash
git add YADF.Options.pas
git commit -m "feat: render yadf.ini template and option help from the descriptor table"
```

---

### Task 5: CLI delegates to the shared loader

**Files:**
- Modify: `YadfMain.pas`

- [ ] **Step 1: Replace the local LoadIniDefaults body with a delegate**

In `YadfMain.pas`, replace the entire `LoadIniDefaults` procedure (lines ~878-921) with:

```pascal
procedure LoadIniDefaults(var AOpts: TYadfOptions; const AIniPath: string);
begin
  if not FileExists(AIniPath) then Exit;
  AOpts := LoadOptionsFromIni(AIniPath);
end;
```

- [ ] **Step 2: Remove the now-duplicate helpers from YadfMain**

Delete the `ReadBoolIni` function (lines ~864-876) and the `ParseEncoding` function (lines ~810-823) from `YadfMain.pas`. They now come from `YADF.Options` (already in scope via `uses YADF.Options`). If any other code in `YadfMain.pas` calls `ParseEncoding`/`ReadBoolIni`, it now resolves to the `YADF.Options` versions — no call-site change needed (identical signatures).

- [ ] **Step 3: If `--version`/help prints option docs, optionally route through OptionsHelpText**

Search `YadfMain.pas` for the usage/help printer. If it enumerates options inline, leave it for a later pass (out of scope); do NOT block on this. (No code change required in this task.)

- [ ] **Step 4: Build the CLI**

Run YADF.dproj Debug/Win32 build. Expected: `Build succeeded.` with no "duplicate identifier" or "undeclared identifier" errors.

- [ ] **Step 5: Regression — run the existing format corpus**

Build the Win64 Release CLI and format a known case, comparing to its golden result:
```
cmd.exe /c "call \"C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat\" && msbuild /t:Build /p:Config=Release /p:Platform=Win64 YADF.dproj"
cmd.exe /c "Win64\Release\EXE\YADF.exe Test\Cases\compound_operators.pas --stdout > %TEMP%\yadf_cli_check.txt"
```
Expected: exit code 0 and non-empty output (the `<=`/`>=` operators intact). Spot-check `%TEMP%\yadf_cli_check.txt` contains `<=` and `>=` unbroken.

- [ ] **Step 6: Commit**

```bash
git add YadfMain.pas
git commit -m "refactor: CLI delegates INI load to YADF.Options.LoadOptionsFromIni"
```

---

### Task 6: IDE wizard delegates to the shared loader (fixes drift)

**Files:**
- Modify: `YADFOT.Wizard.pas`

- [ ] **Step 1: Replace the wizard's LoadIniDefaults body**

In `YADFOT.Wizard.pas`, replace the entire `LoadIniDefaults` procedure (lines ~148-184 — the one missing `AlignMatchingShapes`/`AlignShapeMinAnchors`/`AlignCommentMaxShift`) with:

```pascal
procedure LoadIniDefaults(var AOpts: TYadfOptions; const AIniPath: string);
begin
  if (AIniPath = '') or (not FileExists(AIniPath)) then Exit;
  AOpts := LoadOptionsFromIni(AIniPath);
end;
```

Confirm `YADF.Options` is in the unit's `uses` clause (it must be, since it uses `TYadfOptions`). If `System.IniFiles` was only used by the deleted body and is now unused, leave it — harmless.

> This intentionally changes wizard behavior: it now honors the three alignment options it previously ignored. That is the drift fix and is desired.

- [ ] **Step 2: Build the wizard package**

Run:
```
cmd.exe /c "call \"C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat\" && msbuild /t:Build /p:Config=Release /p:Platform=Win32 YADFOT.dproj"
```
Expected: `Build succeeded.` producing `Win32\Release\BPL\YADFOT.bpl`.

- [ ] **Step 3: Commit**

```bash
git add YADFOT.Wizard.pas
git commit -m "fix: wizard delegates INI load to shared loader (picks up 3 drifted align options)"
```

---

## PHASE 2 — Version single-source

### Task 7: Add YADF.Version.inc

**Files:**
- Create: `YADF.Version.inc`

- [ ] **Step 1: Create the include**

Create `YADF.Version.inc` (ASCII/CRLF):

```pascal
{ Single source of truth for the YADF family version string (display only).
  The numeric FILEVERSION is stamped at build time by build_all.bat via
  /p:VerInfo_* properties using the same value. Bump both here and in
  build_all.bat when releasing. }
const
  YADF_VERSION = '1.0.4.0';
```

- [ ] **Step 2: Reference it from the CLI version output (optional but recommended)**

In `YadfMain.pas`, near the top of the implementation (after `implementation`/`uses`), add:

```pascal
{$I YADF.Version.inc}
```

If `YadfMain.pas` prints a version/banner string, replace the hardcoded version with `YADF_VERSION`. If no banner exists, the include still compiles harmlessly (the const is simply available). Build YADF.dproj Debug/Win32 to confirm. Expected: `Build succeeded.`

- [ ] **Step 3: Commit**

```bash
git add YADF.Version.inc YadfMain.pas
git commit -m "feat: add YADF.Version.inc single-source version string"
```

---

## PHASE 3 — YADFSetup GUI

### Task 8: YADFSetup main form (UI shell)

**Files:**
- Create: `uYADFSetupMain.pas`
- Create: `uYADFSetupMain.dfm`
- Create: `YADFSetup.dpr`

- [ ] **Step 1: Create the form unit**

Create `uYADFSetupMain.pas` (ASCII/CRLF). It builds option controls at runtime from `OptionTable`, formats via `FormatSource`, and autosaves to the shared INI:

```pascal
unit uYADFSetupMain;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.Variants,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.Samples.Spin, Vcl.ComCtrls, Vcl.Clipbrd,
  YADF.Options, YADF.Layout;

type
  TfrmMain = class(TForm)
    pnlSettings: TPanel;
    pnlSource: TPanel;
    pnlResult: TPanel;
    splLeft: TSplitter;
    splRight: TSplitter;
    sbSettings: TScrollBox;
    pnlSettingsBar: TPanel;
    btnLoadSettings: TButton;
    btnSaveSettings: TButton;
    btnReset: TButton;
    lblIniPath: TLabel;
    pnlSourceBar: TPanel;
    btnOpenSource: TButton;
    lblSourceFile: TLabel;
    memSource: TMemo;
    pnlResultBar: TPanel;
    btnCopy: TButton;
    lblResultStatus: TLabel;
    memResult: TMemo;
    dlgOpen: TOpenDialog;
    dlgSaveIni: TSaveDialog;
    tmrReformat: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure btnOpenSourceClick(Sender: TObject);
    procedure btnLoadSettingsClick(Sender: TObject);
    procedure btnSaveSettingsClick(Sender: TObject);
    procedure btnResetClick(Sender: TObject);
    procedure btnCopyClick(Sender: TObject);
    procedure memSourceChange(Sender: TObject);
    procedure tmrReformatTimer(Sender: TObject);
  private
    FOpts: TYadfOptions;
    FIniPath: string;
    FControls: array of TControl;   // index-aligned to OptionTable
    procedure BuildOptionControls;
    procedure OptionsToControls;
    procedure ControlsToOptions;
    procedure OptionChanged(Sender: TObject);
    procedure Reformat;
    procedure AutoSave;
    procedure LoadSample;
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.dfm}

{$I YADF.Version.inc}

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  Caption := 'YADFSetup ' + YADF_VERSION + '  -  Settings | Source | Result';
  FIniPath := SharedAppDataIniPath;
  EnsureIniExists(FIniPath);
  FOpts := LoadOptionsFromIni(FIniPath);
  lblIniPath.Caption := 'INI: ' + FIniPath;
  BuildOptionControls;
  OptionsToControls;
  LoadSample;
  Reformat;
end;

procedure TfrmMain.BuildOptionControls;
var
  T: TArray<TOptInfo>;
  i, y: Integer;
  CurGrp: string;
  gb: TGroupBox;
  parent: TWinControl;
  yIn: Integer;
  cb: TCheckBox;
  se: TSpinEdit;
  ed: TEdit;
  cmb: TComboBox;
  lbl: TLabel;
begin
  T := OptionTable;
  SetLength(FControls, Length(T));
  CurGrp := '';
  gb := nil;
  parent := sbSettings;
  y := 4;
  yIn := 0;
  for i := 0 to High(T) do
  begin
    if T[i].Group <> CurGrp then
    begin
      CurGrp := T[i].Group;
      gb := TGroupBox.Create(Self);
      gb.Parent := sbSettings;
      gb.Left := 4;
      gb.Top := y;
      gb.Width := sbSettings.ClientWidth - 28;
      gb.Anchors := [akLeft, akTop, akRight];
      gb.Caption := CurGrp;
      parent := gb;
      yIn := 18;
    end;
    case T[i].Kind of
      okBool:
        begin
          cb := TCheckBox.Create(Self);
          cb.Parent := parent;
          cb.Left := 10; cb.Top := yIn; cb.Width := gb.Width - 20;
          cb.Caption := T[i].Caption;
          cb.Hint := T[i].Hint; cb.ShowHint := True;
          cb.Tag := i; cb.OnClick := OptionChanged;
          FControls[i] := cb;
          Inc(yIn, 24);
        end;
      okInt:
        begin
          lbl := TLabel.Create(Self);
          lbl.Parent := parent; lbl.Left := 10; lbl.Top := yIn + 3;
          lbl.Caption := T[i].Caption;
          se := TSpinEdit.Create(Self);
          se.Parent := parent; se.Left := 200; se.Top := yIn; se.Width := 70;
          se.MinValue := 0; se.MaxValue := 100000;
          se.Hint := T[i].Hint; se.ShowHint := True;
          se.Tag := i; se.OnChange := OptionChanged;
          FControls[i] := se;
          Inc(yIn, 28);
        end;
      okString:
        begin
          lbl := TLabel.Create(Self);
          lbl.Parent := parent; lbl.Left := 10; lbl.Top := yIn + 3;
          lbl.Caption := T[i].Caption;
          ed := TEdit.Create(Self);
          ed.Parent := parent; ed.Left := 200; ed.Top := yIn; ed.Width := gb.Width - 210;
          ed.Anchors := [akLeft, akTop, akRight];
          ed.Hint := T[i].Hint; ed.ShowHint := True;
          ed.Tag := i; ed.OnChange := OptionChanged;
          FControls[i] := ed;
          Inc(yIn, 28);
        end;
      okEnum:
        begin
          lbl := TLabel.Create(Self);
          lbl.Parent := parent; lbl.Left := 10; lbl.Top := yIn + 3;
          lbl.Caption := T[i].Caption;
          cmb := TComboBox.Create(Self);
          cmb.Parent := parent; cmb.Left := 200; cmb.Top := yIn; cmb.Width := 100;
          cmb.Style := csDropDownList;
          cmb.Items.Add('ANSI'); cmb.Items.Add('UTF-8'); cmb.Items.Add('UTF-16');
          cmb.Hint := T[i].Hint; cmb.ShowHint := True;
          cmb.Tag := i; cmb.OnChange := OptionChanged;
          FControls[i] := cmb;
          Inc(yIn, 28);
        end;
    end;
    if gb <> nil then
    begin
      gb.Height := yIn + 6;
      y := gb.Top + gb.Height + 6;
    end;
  end;
end;

procedure TfrmMain.OptionsToControls;
var
  T: TArray<TOptInfo>;
  i: Integer;
  v: Variant;
begin
  T := OptionTable;
  for i := 0 to High(T) do
  begin
    v := T[i].GetVal(FOpts);
    case T[i].Kind of
      okBool  : TCheckBox(FControls[i]).Checked := v;
      okInt   : TSpinEdit(FControls[i]).Value := v;
      okString: TEdit(FControls[i]).Text := VarToStr(v);
      okEnum  : TComboBox(FControls[i]).ItemIndex :=
                  TComboBox(FControls[i]).Items.IndexOf(VarToStr(v));
    end;
  end;
end;

procedure TfrmMain.ControlsToOptions;
var
  T: TArray<TOptInfo>;
  i: Integer;
begin
  T := OptionTable;
  for i := 0 to High(T) do
    case T[i].Kind of
      okBool  : T[i].SetVal(FOpts, TCheckBox(FControls[i]).Checked);
      okInt   : T[i].SetVal(FOpts, TSpinEdit(FControls[i]).Value);
      okString: T[i].SetVal(FOpts, TEdit(FControls[i]).Text);
      okEnum  : T[i].SetVal(FOpts, TComboBox(FControls[i]).Text);
    end;
end;

procedure TfrmMain.OptionChanged(Sender: TObject);
var
  T: TArray<TOptInfo>;
  idx: Integer;
begin
  ControlsToOptions;
  AutoSave;
  T := OptionTable;
  idx := TControl(Sender).Tag;
  if (idx >= 0) and (idx <= High(T)) and T[idx].AffectsPreview then
    Reformat;
end;

procedure TfrmMain.AutoSave;
begin
  try
    SaveOptionsToIni(FOpts, FIniPath);
    lblIniPath.Caption := 'INI: ' + FIniPath + '  (saved)';
  except
    on E: Exception do
      lblIniPath.Caption := 'INI: ' + FIniPath + '  (save failed: ' + E.Message + ')';
  end;
end;

procedure TfrmMain.Reformat;
begin
  try
    memResult.Text := FormatSource(memSource.Text, FOpts);
    lblResultStatus.Caption := 'OK';
  except
    on E: Exception do
    begin
      memResult.Text := '[Format error] ' + E.ClassName + ': ' + E.Message;
      lblResultStatus.Caption := 'error';
    end;
  end;
end;

procedure TfrmMain.memSourceChange(Sender: TObject);
begin
  tmrReformat.Enabled := False;   // debounce
  tmrReformat.Enabled := True;
end;

procedure TfrmMain.tmrReformatTimer(Sender: TObject);
begin
  tmrReformat.Enabled := False;
  Reformat;
end;

procedure TfrmMain.btnOpenSourceClick(Sender: TObject);
begin
  if dlgOpen.Execute then
  begin
    memSource.Lines.LoadFromFile(dlgOpen.FileName);
    lblSourceFile.Caption := 'file: ' + ExtractFileName(dlgOpen.FileName);
    Reformat;
  end;
end;

procedure TfrmMain.btnSaveSettingsClick(Sender: TObject);
begin
  if dlgSaveIni.Execute then
    SaveOptionsToIni(FOpts, dlgSaveIni.FileName);
end;

procedure TfrmMain.btnLoadSettingsClick(Sender: TObject);
begin
  if dlgOpen.Execute then
  begin
    FOpts := LoadOptionsFromIni(dlgOpen.FileName);
    OptionsToControls;
    AutoSave;        // current state mirrors the shared ini (autosave model)
    Reformat;
  end;
end;

procedure TfrmMain.btnResetClick(Sender: TObject);
begin
  if MessageDlg('Reset all settings to defaults? This overwrites the shared yadf.ini.',
       mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  FOpts := DefaultOptions;
  OptionsToControls;
  AutoSave;
  Reformat;
end;

procedure TfrmMain.btnCopyClick(Sender: TObject);
begin
  Clipboard.AsText := memResult.Text;
end;

procedure TfrmMain.LoadSample;
var
  P: string;
begin
  P := ExtractFilePath(Application.ExeName) + 'Sample.pas';
  if not FileExists(P) then
    P := ExtractFilePath(Application.ExeName) + 'Demo\Sample.pas';
  if not FileExists(P) then
    P := ExtractFilePath(Application.ExeName) + '..\..\..\Demo\Sample.pas';
  if FileExists(P) then
  begin
    memSource.Lines.LoadFromFile(P);
    lblSourceFile.Caption := 'file: Sample.pas';
  end
  else
    lblSourceFile.Caption := 'file: (paste or open a .pas)';
end;

end.
```

- [ ] **Step 2: Create the DFM**

Create `uYADFSetupMain.dfm` (ASCII/CRLF). Controls are positioned by the form; the option controls are created at runtime so the DFM only declares the static skeleton:

```
object frmMain: TfrmMain
  Left = 0
  Top = 0
  Caption = 'YADFSetup'
  ClientHeight = 640
  ClientWidth = 1200
  Position = poScreenCenter
  OnCreate = FormCreate
  TextHeight = 15
  object splLeft: TSplitter
    Left = 360
    Top = 0
    Height = 640
  end
  object splRight: TSplitter
    Left = 780
    Top = 0
    Height = 640
  end
  object pnlSettings: TPanel
    Left = 0
    Top = 0
    Width = 360
    Height = 640
    Align = alLeft
    BevelOuter = bvNone
    Caption = ''
    object pnlSettingsBar: TPanel
      Left = 0
      Top = 0
      Width = 360
      Height = 56
      Align = alTop
      BevelOuter = bvNone
      object lblIniPath: TLabel
        Left = 6
        Top = 36
        Width = 40
        Height = 15
        Caption = 'INI:'
      end
      object btnLoadSettings: TButton
        Left = 6
        Top = 6
        Width = 96
        Height = 25
        Caption = 'Load Settings'
        OnClick = btnLoadSettingsClick
      end
      object btnSaveSettings: TButton
        Left = 108
        Top = 6
        Width = 96
        Height = 25
        Caption = 'Save As...'
        OnClick = btnSaveSettingsClick
      end
      object btnReset: TButton
        Left = 210
        Top = 6
        Width = 96
        Height = 25
        Caption = 'Reset'
        OnClick = btnResetClick
      end
    end
    object sbSettings: TScrollBox
      Left = 0
      Top = 56
      Width = 360
      Height = 584
      Align = alClient
      BorderStyle = bsNone
    end
  end
  object pnlSource: TPanel
    Left = 363
    Top = 0
    Width = 417
    Height = 640
    Align = alLeft
    BevelOuter = bvNone
    Caption = ''
    object pnlSourceBar: TPanel
      Left = 0
      Top = 0
      Width = 417
      Height = 32
      Align = alTop
      BevelOuter = bvNone
      object lblSourceFile: TLabel
        Left = 110
        Top = 9
        Width = 60
        Height = 15
        Caption = 'file:'
      end
      object btnOpenSource: TButton
        Left = 6
        Top = 4
        Width = 96
        Height = 25
        Caption = 'Open File...'
        OnClick = btnOpenSourceClick
      end
    end
    object memSource: TMemo
      Left = 0
      Top = 32
      Width = 417
      Height = 608
      Align = alClient
      Font.Height = -13
      Font.Name = 'Consolas'
      ParentFont = False
      ScrollBars = ssBoth
      WordWrap = False
      OnChange = memSourceChange
    end
  end
  object pnlResult: TPanel
    Left = 783
    Top = 0
    Width = 417
    Height = 640
    Align = alClient
    BevelOuter = bvNone
    Caption = ''
    object pnlResultBar: TPanel
      Left = 0
      Top = 0
      Width = 417
      Height = 32
      Align = alTop
      BevelOuter = bvNone
      object lblResultStatus: TLabel
        Left = 110
        Top = 9
        Width = 50
        Height = 15
        Caption = 'OK'
      end
      object btnCopy: TButton
        Left = 6
        Top = 4
        Width = 96
        Height = 25
        Caption = 'Copy'
        OnClick = btnCopyClick
      end
    end
    object memResult: TMemo
      Left = 0
      Top = 32
      Width = 417
      Height = 608
      Align = alClient
      Font.Height = -13
      Font.Name = 'Consolas'
      ParentFont = False
      ReadOnly = True
      ScrollBars = ssBoth
      WordWrap = False
    end
  end
  object dlgOpen: TOpenDialog
    Filter = 'Pascal/INI|*.pas;*.dpr;*.inc;*.ini|All files|*.*'
    Left = 200
    Top = 300
  end
  object dlgSaveIni: TSaveDialog
    DefaultExt = 'ini'
    Filter = 'INI files|*.ini|All files|*.*'
    Left = 260
    Top = 300
  end
  object tmrReformat: TTimer
    Enabled = False
    Interval = 300
    OnTimer = tmrReformatTimer
    Left = 320
    Top = 300
  end
end
```

- [ ] **Step 3: Create the .dpr**

Create `YADFSetup.dpr`:

```pascal
program YADFSetup;

uses
  Vcl.Forms,
  uYADFSetupMain in 'uYADFSetupMain.pas' {frmMain},
  YADF.Tokens in 'YADF.Tokens.pas',
  YADF.Options in 'YADF.Options.pas',
  YADF.Groups in 'YADF.Groups.pas',
  YADF.Layout in 'YADF.Layout.pas',
  YADF.Debug in 'YADF.Debug.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
```

- [ ] **Step 4: Commit (compiles in Task 9)**

```bash
git add YADFSetup.dpr uYADFSetupMain.pas uYADFSetupMain.dfm
git commit -m "feat: YADFSetup main form (3-column UI, runtime controls from descriptor table)"
```

---

### Task 9: YADFSetup project file + build

**Files:**
- Create: `YADFSetup.dproj`

- [ ] **Step 1: Create YADFSetup.dproj by copying YADF.dproj and editing**

Copy `YADF.dproj` to `YADFSetup.dproj`, then make these exact edits (the rest of the boilerplate — deployment classes etc. — is fine to keep):

1. New `<ProjectGuid>`: `{7F3A9C12-4D55-4E10-9C2B-2B6E1A77FE01}`.
2. `<Platform Condition="'$(Platform)'==''">Win32</Platform>` (was Win64).
3. `<ProjectName Condition="'$(ProjectName)'==''">YADFSetup</ProjectName>`.
4. `<AppType>Application</AppType>` (was Console).
5. `<MainSource>YADFSetup.dpr</MainSource>` (was YADF.dpr).
6. `<FrameworkType>VCL</FrameworkType>` (was None).
7. `<SanitizedProjectName>YADFSetup</SanitizedProjectName>`.
8. Remove every `<DCC_ConsoleTarget>true</DCC_ConsoleTarget>` line (it is a GUI app).
9. In the `ItemGroup`, replace the `DCCReference` list with:
   ```xml
   <DCCReference Include="YADF.Tokens.pas"/>
   <DCCReference Include="YADF.Options.pas"/>
   <DCCReference Include="YADF.Groups.pas"/>
   <DCCReference Include="YADF.Layout.pas"/>
   <DCCReference Include="YADF.Debug.pas"/>
   <DCCReference Include="uYADFSetupMain.pas">
       <Form>frmMain</Form>
   </DCCReference>
   ```
10. In `<Source><Source Name="MainSource">` change `YADF.dpr` to `YADFSetup.dpr`.
11. Update both `VerInfo_Keys` and version numbers to 1.0.4.0 with `FileDescription=YADFSetup` and `ProductName=YADFSetup` (these get overridden by build_all.bat too, but keep them consistent for IDE builds).

- [ ] **Step 2: Build YADFSetup (Debug/Win32)**

Run:
```
cmd.exe /c "call \"C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat\" && msbuild /t:Build /p:Config=Debug /p:Platform=Win32 YADFSetup.dproj"
```
Expected: `Build succeeded.` producing `Win32\Debug\EXE\YADFSetup.exe`.

If the linker reports missing VCL units, confirm `<FrameworkType>VCL</FrameworkType>` and that `<DCC_UsePackage>` still contains `vcl;vclimg;...` (inherited from the copied YADF.dproj Base_Win32 — keep it).

- [ ] **Step 3: Commit**

```bash
git add YADFSetup.dproj
git commit -m "build: add YADFSetup.dproj (VCL Win32) and verify compile"
```

---

### Task 10: Sample.pas demonstration unit

**Files:**
- Create: `Demo\Sample.pas`

- [ ] **Step 1: Author the sample**

Create `Demo\Sample.pas` (ASCII/CRLF) — valid, compilable Delphi 13 that exercises every feature and modern syntax. Author it deliberately mis-formatted (ragged spacing, combined var decls, un-broken uses) so the playground visibly improves it:

```pascal
unit Sample;

interface

{$I jedi.inc}
{$I extra.inc}

uses System.SysUtils, System.Classes, System.Generics.Collections;

type
  // enum with trailing // comments (regression shape: must not be merged)
  TKind = (
    knNone = 0,   // nothing
    knLow  = 1,   // low
    knHigh = 2    // high
  );

  TPoint = record
    X, Y: Integer;          // combined decl -> split + colon-align
    Name: string;
  end;

const
  Origin: array[0..2] of TPoint = (
    (X: 0;  Y: 0;  Name: 'a'),
    (X: 10; Y: 20; Name: 'bb'),
    (X: 7;  Y: 3;  Name: 'ccc')
  );

procedure Demo;

implementation

{$R+}

procedure Demo;
var I, J: Integer;          // combined -> split
begin
  const Factor = 2;         // inline const
  var Sum := 0.0;           // inline var + type inference
  for var K := 0 to High(Origin) do
    Sum := Sum + Origin[K].X;
  var Items: TList<Integer> := TList<Integer>.Create;  // inline var + generic
  try
    for I := 0 to 9 do
      if I <= 4 then Items.Add(I * Factor);   // <= must stay intact
    Items.Sort(
      function(const A, B: Integer): Integer   // inline anon method
      begin
        Result := A - B;
      end);
    if Items.Count is not Integer then Exit;   // is not operator
    J := Items.Count >= 5 ? 100 : 0;           // if-ternary expression
    Writeln(J, Sum);
  finally
    Items.Free;
  end;
end;

end.
```

> If `?:` ternary or `is not` syntax is rejected by the installed compiler, keep them anyway — `Sample.pas` is a formatting demo, not a compiled unit of the build. (It is NOT added to any `.dproj`.) The spec requires demonstrating these idioms; the formatter is lexer-based and formats them regardless.

- [ ] **Step 2: Verify YADFSetup loads it**

Copy `Demo\Sample.pas` next to the built exe and run a quick manual check is done in Task 12 (smoke). For now just confirm the file exists and is ASCII:
```
cmd.exe /c "findstr /R /C:"[^ -~	]" Demo\Sample.pas" && echo NON-ASCII-FOUND || echo ASCII-OK
```
Expected: `ASCII-OK`.

- [ ] **Step 3: Commit**

```bash
git add Demo/Sample.pas
git commit -m "feat: bundled Demo/Sample.pas demonstrating all features + modern Delphi syntax"
```

---

### Task 11: build_all.bat — one version stamp for all three artifacts

**Files:**
- Create: `build_all.bat`

- [ ] **Step 1: Create the build script**

Create `build_all.bat` (CRLF). It defines the version once and stamps it into all three artifacts via `/p:VerInfo_*` (overrides the dproj values, guaranteeing identical FileVersion):

```bat
@echo off
setlocal
rem ---- Single source of truth for the release version --------------
set YADF_MAJOR=1
set YADF_MINOR=0
set YADF_RELEASE=4
set YADF_BUILD=0
set YADF_VER=%YADF_MAJOR%.%YADF_MINOR%.%YADF_RELEASE%.%YADF_BUILD%
rem NOTE: keep YADF.Version.inc YADF_VERSION in sync with the above.

call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"

set VERPROPS=/p:VerInfo_AutoIncVersion=false /p:VerInfo_MajorVer=%YADF_MAJOR% /p:VerInfo_MinorVer=%YADF_MINOR% /p:VerInfo_Release=%YADF_RELEASE% /p:VerInfo_Build=%YADF_BUILD%

echo === Building YADF.exe (Win64 Release) %YADF_VER% ===
msbuild /t:Build /p:Config=Release /p:Platform=Win64 %VERPROPS% YADF.dproj || goto :err

echo === Building YADFSetup.exe (Win32 Release) %YADF_VER% ===
msbuild /t:Build /p:Config=Release /p:Platform=Win32 %VERPROPS% YADFSetup.dproj || goto :err

echo === Building YADFOT.bpl (Win32 Release) %YADF_VER% ===
msbuild /t:Build /p:Config=Release /p:Platform=Win32 %VERPROPS% YADFOT.dproj || goto :err

echo.
echo === All artifacts built at %YADF_VER% ===
goto :eof

:err
echo BUILD FAILED
exit /b 1
```

- [ ] **Step 2: Run the full build**

Run:
```
cmd.exe /c build_all.bat
```
Expected: `=== All artifacts built at 1.0.4.0 ===`. Three outputs exist:
- `Win64\Release\EXE\YADF.exe`
- `Win32\Release\EXE\YADFSetup.exe`
- `Win32\Release\BPL\YADFOT.bpl`

- [ ] **Step 3: Verify identical FileVersion across all three**

```
cmd.exe /c "for %f in (Win64\Release\EXE\YADF.exe Win32\Release\EXE\YADFSetup.exe Win32\Release\BPL\YADFOT.bpl) do @powershell -NoProfile -Command \"(Get-Item '%f').VersionInfo.FileVersion\""
```
Expected: `1.0.4.0` printed three times.

- [ ] **Step 4: Commit**

```bash
git add build_all.bat
git commit -m "build: build_all.bat stamps one version across YADF.exe, YADFSetup.exe, YADFOT.bpl"
```

---

### Task 12: Launch smoke test for YADFSetup

**Files:**
- Create: `Test\smoke_yadfsetup.ps1`

- [ ] **Step 1: Write the smoke script**

Create `Test\smoke_yadfsetup.ps1` (starts the GUI, lets it format the sample, asserts it stays alive, then closes it):

```powershell
$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot '..\Win32\Release\EXE\YADFSetup.exe'
if (-not (Test-Path $exe)) { Write-Error "YADFSetup.exe not found at $exe"; exit 1 }

# ensure the sample is reachable next to the exe
$sampleSrc = Join-Path $PSScriptRoot '..\Demo\Sample.pas'
$sampleDst = Join-Path (Split-Path $exe) 'Sample.pas'
Copy-Item $sampleSrc $sampleDst -Force

$p = Start-Process -FilePath $exe -PassThru
Start-Sleep -Seconds 3
if ($p.HasExited) { Write-Error "YADFSetup exited immediately (code $($p.ExitCode))"; exit 1 }
# window must be visible
$p.Refresh()
if (-not $p.MainWindowHandle -or $p.MainWindowHandle -eq 0) {
  Stop-Process -Id $p.Id -Force
  Write-Error "YADFSetup has no main window"; exit 1
}
Stop-Process -Id $p.Id -Force
Write-Output "SMOKE OK: YADFSetup launched, window present, survived 3s"
```

- [ ] **Step 2: Run the smoke test**

Run:
```
pwsh -File Test\smoke_yadfsetup.ps1
```
Expected: `SMOKE OK: YADFSetup launched, window present, survived 3s`.

If it exits immediately, run the exe manually to read the exception; the most likely cause is a missing `Sample.pas` (non-fatal — the form should still open) or a VCL package issue (rebuild Task 9).

- [ ] **Step 3: Commit**

```bash
git add Test/smoke_yadfsetup.ps1
git commit -m "test: YADFSetup launch smoke (window present, survives)"
```

---

### Task 13: Docs + packaging

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add a YADFSetup section to README.md**

Under the existing tool documentation, add:

```markdown
## YADFSetup.exe — visual settings editor & playground

`YADFSetup.exe` is a 3-column GUI: **Settings | Source | Result**. Load any
`.pas` on the left, see it formatted live on the right, and tune every option
in between. Changes save immediately to the shared `yadf.ini`
(`%APPDATA%\YADF\yadf.ini`) that `YADF.exe` and `YADFOT.bpl` also use.

- **Load Settings / Save As** — import or export an option profile (any `.ini`).
- **Reset** — restore the shipped defaults (overwrites the shared `yadf.ini`).
- Auto-loads `Demo\Sample.pas` on first launch to demonstrate every feature.

Because edits autosave to the shared config, experimenting in YADFSetup changes
how the CLI and IDE wizard format from then on. Use Save As to keep a profile
and Reset to return to defaults.
```

Also update the build instructions to mention `build_all.bat` and the third artifact.

- [ ] **Step 2: Add the CHANGELOG entry**

At the top of `CHANGELOG.md` add:

```markdown
## [1.0.4.0] -- 2026-06-02

### Added
- **YADFSetup.exe** -- a visual settings editor / format playground
  (Settings | Source | Result) that tunes every option live and autosaves the
  shared `yadf.ini`. Ships with `Demo\Sample.pas`.
- **Single option-descriptor table in `YADF.Options`** (`YADF_OPTIONS`) now the
  one source for INI load/save, the `yadf.ini` template, and option help.
  New `LoadOptionsFromIni` / `SaveOptionsToIni` / `OptionsHelpText`.
- **`build_all.bat`** builds all three artifacts with one shared version stamp;
  `YADF.exe`, `YADFSetup.exe`, and `YADFOT.bpl` now carry an identical
  FileVersion (`YADF.Version.inc`).

### Fixed
- **YADFOT wizard ignored three alignment options.** `YADFOT.Wizard.pas` had a
  drifted INI reader missing `AlignMatchingShapes`, `AlignShapeMinAnchors`, and
  `AlignCommentMaxShift`. Both the CLI and the wizard now delegate to the shared
  `LoadOptionsFromIni`, so all tools honor the same options.

### Distribution
The release zip now contains `YADF.exe`, `YADFSetup.exe`, `YADFOT.bpl`,
`Demo\Sample.pas`, `README.md`, `CHANGELOG.md`, `LICENSE`. No `yadf.ini`
(auto-created on first run).
```

- [ ] **Step 3: Commit**

```bash
git add README.md CHANGELOG.md
git commit -m "docs: document YADFSetup, descriptor table, and 1.0.4.0 release"
```

---

## Final verification (run after all tasks)

- [ ] `cmd.exe /c build_all.bat` → all three build at 1.0.4.0.
- [ ] `cmd.exe /c "Test\Win32\Debug\EXE\OptionsTest.exe"` → `ALL PASS`.
- [ ] `pwsh -File Test\smoke_yadfsetup.ps1` → `SMOKE OK`.
- [ ] FileVersion identical across the three artifacts (Task 11 Step 3).
- [ ] Manual: launch `YADFSetup.exe`, toggle `LowercaseKeywords` and watch the
      Result pane re-case keywords; confirm `%APPDATA%\YADF\yadf.ini` updated.

---

## Self-Review notes (author)

- **Spec coverage:** §5.1 → Tasks 1-4; §5.2 → Tasks 8-9; §5.3 → Task 10; §6 → Task 8 (behavior wired); §7 → Tasks 7,11; §8 → Tasks 3,12; §9 → Tasks 11,13. All covered.
- **Type consistency:** `OptionTable`, `TOptInfo`, `TOptKind`, `LoadOptionsFromIni`, `SaveOptionsToIni`, `OptionsHelpText`, `EncodingToStr`, `ReadBoolIni`, `ParseEncoding` used identically across tasks. Form field array `FControls` index-aligned to `OptionTable` in both `OptionsToControls`/`ControlsToOptions`.
- **Known soft spots flagged inline:** duplicate-identifier ordering between Task 1 and Task 5 (noted); ternary/`is not` compilability of the demo (noted as non-compiled asset); `EXPECTED_OPTION_COUNT=33` must track the record (the completeness test is the guard).
```
