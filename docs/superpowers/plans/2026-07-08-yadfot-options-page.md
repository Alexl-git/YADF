# YADFOT Tools > Options Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a native `Tools > Options > Third Party > YADF` page to the YADFOT IDE wizard that edits the shared `%APPDATA%\YADF\yadf.ini` through the same `OptionTable` API as YADFSetup and the CLI.

**Architecture:** One new self-contained unit `YADFOT.Options.pas` holds a parameterized `INTAAddInOptions` page class, a single generic `TFrame` whose controls are code-built by iterating `YADF.Options.OptionTable` (mirroring YADFSetup's `BuildOptionControls`), and idempotent `Register`/`Unregister` procedures with a `finalization` teardown net. `YADFOT.Wizard.pas` is wired to register on package load and unregister via the wizard's `Destroyed` method (primary) + the unit finalization (secondary). The new unit is added to `YADFOT.dpk`'s `contains` clause and `YADFOT.dproj`'s `<DCCReference>` list.

**Tech Stack:** Delphi 13 (RAD Studio 37.0), VCL, ToolsAPI (OTA), Win32 design-time BPL. No new third-party dependencies.

## Global Constraints

- **Encoding:** all `.pas` files are strict 7-bit ASCII, CRLF line endings, no BOM, no Unicode chars. (`c:\Projects\CLAUDE.md`.)
- **DocInsight:** every public/published type and method gets a `///` XML doc-comment (`<summary>`, `<remarks>` for ownership/thread-safety). Private helpers only when an invariant is non-obvious.
- **Delphi 13 idiom:** `X:= Y` assignment spacing style matches surrounding YADF code (`AssignNoSpaceBefore`), `FMyField`/`TMyClass` naming.
- **No unit tests possible.** OTA UI is not headless-testable (per `docs/PORT-tools-options-page.md` section 5/8). The per-task verification gate is a **clean compile of the Win32 Debug BPL** (`BUILD_EXITCODE=0`, no `[dcc] Error`), NOT a unit test. Final acceptance is a manual in-IDE check the user performs (this plan's last section).
- **Build recipe:** use the `delphi-build` skill's recipe — a 3-line wrapper `.bat` (`rsvars` -> `cd` -> `msbuild`) run from PowerShell `Start-Process -Wait` with output redirected to a log, then read the log. Do NOT use the MCP build tool or `cmd.exe /c build.bat` from Bash. Build **Win32 Debug** specifically (`build_all.bat` only builds Release, which the IDE does not load).
- **Reference files** (read for exact patterns, do not import): `C:\Projects\Delphi-RAG-lint\src\delphi-plugin\DragLint.Plugin.Options.pas` (page class + register/unregister), `DragLint.Plugin.OptionsFrames.pas` (frame + control helpers). YADF's own `uYADFSetupMain.pas` lines 127-266 is the generic-loop pattern to adapt.
- **Do NOT commit until the Debug BPL builds clean.** Commit + push (via `.private\GITPush.bat "<msg>"`) once green. Publishing happens after everything is done, per the user.

---

### Task 1: Create `YADFOT.Options.pas` (page class + generic frame + register/unregister + finalization)

This is the whole new unit in one task: it is a single self-contained deliverable that only compiles once the `.dpk`/`.dproj` reference it (Task 3), so its real verification comes at Task 4. Splitting the page class from the frame into separate steps would produce two half-units that cannot compile independently.

**Files:**
- Create: `c:\Projects\YADF\YADFOT.Options.pas`

**Interfaces:**
- Consumes (from `YADF.Options.pas`, already present): `TYadfOptions`, `TOptInfo`, `TOptKind` (`okBool`/`okInt`/`okString`/`okEnum`), `OptionTable: TArray<TOptInfo>`, `LoadOptionsFromIni(const APath): TYadfOptions`, `SaveOptionsToIni(const AOpts; const APath)`, `EnsureIniExists(const APath): Boolean`, `SharedAppDataIniPath: string`, `EncodingToStr`/`ParseEncoding`.
- Produces (used by Task 2 in `YADFOT.Wizard.pas`): `procedure RegisterYADFOptions;` and `procedure UnregisterYADFOptions;` (both in the `interface` section, both idempotent).

- [ ] **Step 1: Write the complete unit**

Create `c:\Projects\YADF\YADFOT.Options.pas` with exactly this content (strict ASCII, CRLF):

```pascal
{
  YADFOT.Options -- Tools > Options > Third Party > YADF page for YADFOT.

  Copyright (c) 2026 Alexander Liberov

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.

  A native IDE Options page that edits the shared per-user
  %APPDATA%\YADF\yadf.ini through the SAME YADF.Options descriptor table
  (OptionTable) as YADFSetup.exe and the CLI, so all three converge on one
  file with no duplicated schema. The page is a single generic TFrame whose
  controls are built by iterating OptionTable -- adding a field to
  TYadfOptions/OptionTable makes it appear here automatically.

  Teardown: RegisterYADFOptions runs from YADFOT.Wizard.Register on package
  load; UnregisterYADFOptions runs from the wizard's Destroyed method (the
  primary hook, before the BPL code segment is dropped) AND from this unit's
  finalization (secondary net). Both are idempotent.
}

unit YADFOT.Options;

interface

/// <summary>Register the "Third Party > YADF" page with the IDE's environment
/// options service. Called from YADFOT.Wizard.Register on package load.
/// Idempotent-safe: re-registering after an unregister re-adds the page.</summary>
procedure RegisterYADFOptions;

/// <summary>Unregister the YADF options page(s). Called from the wizard's
/// Destroyed method (primary) and this unit's finalization (secondary).
/// Idempotent: guarded on an empty ref array, and clears the array after,
/// so a second call is a safe no-op.</summary>
procedure UnregisterYADFOptions;

implementation

uses
  System.SysUtils
  , System.Classes
  , System.Variants
  , Vcl.Controls
  , Vcl.Forms
  , Vcl.StdCtrls
  , Vcl.ExtCtrls
  , Vcl.Samples.Spin
  , ToolsAPI
  , YADF.Options
  ;

type
  /// <summary>The generic Tools > Options frame. Controls are code-built by
  /// iterating YADF.Options.OptionTable, grouped by TOptInfo.Group into
  /// TGroupBoxes inside a scrolling host -- the same layout YADFSetup uses.
  /// Load reads the shared yadf.ini into the controls; Save writes them back
  /// (read-modify-write, so a future page split cannot clobber other fields).</summary>
  /// <remarks>Not thread-safe; the IDE drives Load/Save on the main thread.
  /// FControls is index-aligned to OptionTable. The page is inert until OK
  /// (no live autosave, unlike YADFSetup).</remarks>
  TYadfOptionsFrame = class(TFrame)
  private
    FOpts    : TYadfOptions;
    FScroll  : TScrollBox;
    FControls: array of TControl;   // index-aligned to OptionTable
    FUpdating: Boolean;             // True while pushing FOpts -> controls
    procedure BuildControls;
    procedure OptionsToControls;
    procedure ControlsToOptions;
    function  IniPath: string;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Read the shared yadf.ini into FOpts and populate the controls.</summary>
    procedure Load;
    /// <summary>Re-read the record fresh, apply this frame's controls, write it back.</summary>
    procedure Save;
  end;

  TYadfOptionsFrameClass = class of TYadfOptionsFrame;

  /// <summary>INTAAddInOptions page carrying one YADF frame class. GetArea
  /// returns '' so the page lands under the "Third Party" branch; a dotted
  /// caption would nest sub-pages under a 'YADF' node. One instance per page;
  /// parameterized (ACaption, AFrameClass) so a later N-page split is a
  /// one-line change.</summary>
  TYadfOptionsPage = class(TInterfacedObject, INTAAddInOptions)
  private
    FCaption   : string;
    FFrameClass: TCustomFrameClass;
    FFrame     : TYadfOptionsFrame;
  public
    constructor Create(const ACaption: string; AFrameClass: TCustomFrameClass);
    { INTAAddInOptions }
    function  GetArea         : string;
    function  GetCaption      : string;
    function  GetFrameClass   : TCustomFrameClass;
    procedure FrameCreated(AFrame: TCustomFrame);
    procedure DialogClosed(Accepted: Boolean);
    function  ValidateContents   : Boolean;
    function  GetHelpContext     : Integer;
    function  IncludeInIDEInsight: Boolean;
  end;

{ ==================== TYadfOptionsFrame ==================== }

constructor TYadfOptionsFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Width := 520;
  Height:= 460;
  FScroll:= TScrollBox.Create(Self);
  FScroll.Parent  := Self;
  FScroll.Align   := alClient;
  FScroll.BorderStyle:= bsNone;
  BuildControls;
end;

function TYadfOptionsFrame.IniPath: string;
begin
  // The IDE options page always edits the shared per-user profile -- the same
  // file YADFSetup edits by default and tier 4 of the wizard's resolution.
  Result:= SharedAppDataIniPath;
end;

procedure TYadfOptionsFrame.BuildControls;
var
  T     : TArray<TOptInfo>;
  i, y  : Integer;
  CurGrp: string;
  gb    : TGroupBox;
  parent: TWinControl;
  yIn   : Integer;
  cb    : TCheckBox;
  se    : TSpinEdit;
  ed    : TEdit;
  cmb   : TComboBox;
  lbl   : TLabel;
begin
  // Adapts YADFSetup.BuildOptionControls: one TGroupBox per TOptInfo.Group,
  // one control per row keyed by Kind, stored index-aligned in FControls.
  T:= OptionTable;
  SetLength(FControls, Length(T));
  CurGrp:= '';
  gb    := nil;
  parent:= FScroll;
  y     := 4;
  yIn   := 0;
  for i:= 0 to High(T) do
  begin
    if T[i].Group <> CurGrp then
    begin
      CurGrp:= T[i].Group;
      gb:= TGroupBox.Create(Self);
      gb.Parent := FScroll;
      gb.Left   := 4;
      gb.Top    := y;
      gb.Width  := FScroll.ClientWidth - 28;
      gb.Anchors:= [akLeft, akTop, akRight];
      gb.Caption:= CurGrp;
      parent:= gb;
      yIn   := 18;
    end;
    case T[i].Kind of
      okBool:
        begin
          cb:= TCheckBox.Create(Self);
          cb.Parent := parent;
          cb.Left   := 10; cb.Top:= yIn; cb.Width:= gb.Width - 20;
          cb.Caption:= T[i].Caption;
          cb.Hint   := T[i].Hint; cb.ShowHint:= True;
          cb.Tag    := i;
          FControls[i]:= cb;
          Inc(yIn, 24);
        end;
      okInt:
        begin
          lbl:= TLabel.Create(Self);
          lbl.Parent := parent; lbl.Left:= 10; lbl.Top:= yIn + 3;
          lbl.Caption:= T[i].Caption;
          se:= TSpinEdit.Create(Self);
          se.Parent := parent; se.Left:= 240; se.Top:= yIn; se.Width:= 80;
          se.MinValue:= 0; se.MaxValue:= 100000;
          se.Hint   := T[i].Hint; se.ShowHint:= True;
          se.Tag    := i;
          FControls[i]:= se;
          Inc(yIn, 28);
        end;
      okString:
        begin
          lbl:= TLabel.Create(Self);
          lbl.Parent := parent; lbl.Left:= 10; lbl.Top:= yIn + 3;
          lbl.Caption:= T[i].Caption;
          ed:= TEdit.Create(Self);
          ed.Parent := parent; ed.Left:= 240; ed.Top:= yIn; ed.Width:= gb.Width - 250;
          ed.Anchors:= [akLeft, akTop, akRight];
          ed.Hint   := T[i].Hint; ed.ShowHint:= True;
          ed.Tag    := i;
          FControls[i]:= ed;
          Inc(yIn, 28);
        end;
      okEnum:
        begin
          lbl:= TLabel.Create(Self);
          lbl.Parent := parent; lbl.Left:= 10; lbl.Top:= yIn + 3;
          lbl.Caption:= T[i].Caption;
          cmb:= TComboBox.Create(Self);
          cmb.Parent := parent; cmb.Left:= 240; cmb.Top:= yIn; cmb.Width:= 110;
          cmb.Style  := csDropDownList;
          cmb.Items.Add('ANSI'); cmb.Items.Add('UTF-8'); cmb.Items.Add('UTF-16');
          cmb.Hint   := T[i].Hint; cmb.ShowHint:= True;
          cmb.Tag    := i;
          FControls[i]:= cmb;
          Inc(yIn, 28);
        end;
    end;
    if gb <> nil then
    begin
      gb.Height:= yIn + 6;
      y:= gb.Top + gb.Height + 6;
    end;
  end;
end;

procedure TYadfOptionsFrame.OptionsToControls;
var
  T: TArray<TOptInfo>;
  i: Integer;
  v: Variant;
begin
  // Programmatic writes fire OnClick/OnChange, but no handlers are wired on
  // this inert page; FUpdating is kept only to match YADFSetup's shape.
  T:= OptionTable;
  FUpdating:= True;
  try
    for i:= 0 to High(T) do
    begin
      v:= T[i].GetVal(FOpts);
      case T[i].Kind of
        okBool  : TCheckBox(FControls[i]).Checked:= v;
        okInt   : TSpinEdit(FControls[i]).Value  := v;
        okString: TEdit(FControls[i]).Text       := VarToStr(v);
        okEnum  : TComboBox(FControls[i]).ItemIndex:=
                    TComboBox(FControls[i]).Items.IndexOf(VarToStr(v));
      end;
    end;
  finally
    FUpdating:= False;
  end;
end;

procedure TYadfOptionsFrame.ControlsToOptions;
var
  T: TArray<TOptInfo>;
  i: Integer;
begin
  T:= OptionTable;
  for i:= 0 to High(T) do
    case T[i].Kind of
      okBool  : T[i].SetVal(FOpts, TCheckBox(FControls[i]).Checked);
      okInt   : T[i].SetVal(FOpts, TSpinEdit(FControls[i]).Value);
      okString: T[i].SetVal(FOpts, TEdit(FControls[i]).Text);
      okEnum  : T[i].SetVal(FOpts, TComboBox(FControls[i]).Text);
    end;
end;

procedure TYadfOptionsFrame.Load;
var
  P: string;
begin
  P:= IniPath;
  EnsureIniExists(P);
  FOpts:= LoadOptionsFromIni(P);
  OptionsToControls;
end;

procedure TYadfOptionsFrame.Save;
var
  P: string;
begin
  // Read-modify-write: re-read the record fresh so any field NOT surfaced as a
  // control survives (none today; a guard for a future page split), then apply
  // this frame's controls and write the whole record back through the shared
  // OptionTable serializer (comments in the template are preserved).
  P:= IniPath;
  FOpts:= LoadOptionsFromIni(P);
  ControlsToOptions;
  SaveOptionsToIni(FOpts, P);
end;

{ ==================== TYadfOptionsPage ==================== }

constructor TYadfOptionsPage.Create(const ACaption: string; AFrameClass: TCustomFrameClass);
begin
  inherited Create;
  FCaption   := ACaption;
  FFrameClass:= AFrameClass;
end;

function TYadfOptionsPage.GetArea: string;
begin
  // Empty area = "Third Party" branch in the Options left tree.
  Result:= '';
end;

function TYadfOptionsPage.GetCaption: string;
begin
  Result:= FCaption;
end;

function TYadfOptionsPage.GetFrameClass: TCustomFrameClass;
begin
  Result:= FFrameClass;
end;

procedure TYadfOptionsPage.FrameCreated(AFrame: TCustomFrame);
begin
  if AFrame is TYadfOptionsFrame then
  begin
    FFrame:= TYadfOptionsFrame(AFrame);
    FFrame.Load;
  end;
end;

procedure TYadfOptionsPage.DialogClosed(Accepted: Boolean);
begin
  // Commit on OK (IDE convention); discard on Cancel. Nil the ref either way --
  // the IDE may destroy/recreate the frame between dialog opens.
  if Accepted and Assigned(FFrame) then FFrame.Save;
  FFrame:= nil;
end;

function TYadfOptionsPage.ValidateContents: Boolean;
begin
  Result:= True;
end;

function TYadfOptionsPage.GetHelpContext: Integer;
begin
  Result:= 0;
end;

function TYadfOptionsPage.IncludeInIDEInsight: Boolean;
begin
  Result:= True;
end;

{ ==================== register / unregister ==================== }

var
  // Kept so Unregister hands back the EXACT instances we registered.
  GOptions: array of INTAAddInOptions;

procedure RegisterYADFOptions;
var
  Svc: INTAEnvironmentOptionsServices;

  procedure Add(const ACap: string; AFC: TCustomFrameClass);
  var
    O: INTAAddInOptions;
  begin
    O:= TYadfOptionsPage.Create(ACap, AFC);
    Svc.RegisterAddInOptions(O);
    GOptions:= GOptions + [O];
  end;

begin
  if not Supports(BorlandIDEServices, INTAEnvironmentOptionsServices, Svc) then Exit;
  Add('YADF', TYadfOptionsFrame);   // single page; add more Add(...) to split later
end;

procedure UnregisterYADFOptions;
var
  Svc: INTAEnvironmentOptionsServices;
  O  : INTAAddInOptions;
begin
  if Length(GOptions) = 0 then Exit;
  if Supports(BorlandIDEServices, INTAEnvironmentOptionsServices, Svc) then
    for O in GOptions do
      try Svc.UnregisterAddInOptions(O); except end;
  SetLength(GOptions, 0);
end;

initialization

finalization
  UnregisterYADFOptions;   // secondary net; wizard's Destroyed is primary

end.
```

- [ ] **Step 2: Verify strict-ASCII / CRLF encoding**

Run (PowerShell): check no non-ASCII byte and that CRLF endings are present.
```powershell
$b = [System.IO.File]::ReadAllBytes("c:\Projects\YADF\YADFOT.Options.pas")
"NonASCII=$(( $b | Where-Object { $_ -gt 127 } ).Count)  HasCRLF=$([bool]([System.Text.Encoding]::ASCII.GetString($b) -match "`r`n"))"
```
Expected: `NonASCII=0  HasCRLF=True`. If `NonASCII` > 0, find and replace the offending char with ASCII; if `HasCRLF=False`, re-save with CRLF.

- [ ] **Step 3: Do NOT commit yet** — this unit does not compile until Tasks 2-3 reference it (the `.dpk` gotcha). Commit happens at Task 4 after a green build.

---

### Task 2: Wire register + teardown into `YADFOT.Wizard.pas`

**Files:**
- Modify: `c:\Projects\YADF\YADFOT.Wizard.pas` (uses clause ~line 45-47; `TYadfotMenuWizard` decl ~line 53-62; implementation near `Execute` ~line 575-578; `Register` ~line 632-640)

**Interfaces:**
- Consumes: `RegisterYADFOptions`, `UnregisterYADFOptions` from `YADFOT.Options` (Task 1).
- Produces: nothing new consumed downstream; this is the integration point.

- [ ] **Step 1: Add `YADF.Options` alias unit to the `uses` clause**

In the `implementation uses` clause (currently ends `, YADF.Layout ;`), add the new unit. Change:
```pascal
  , YADF.Options
  , YADF.Layout
  ;
```
to:
```pascal
  , YADF.Options
  , YADF.Layout
  , YADFOT.Options
  ;
```

- [ ] **Step 2: Add the `Destroyed` override to `TYadfotMenuWizard`'s declaration**

In the `TYadfotMenuWizard = class(...)` declaration, the `public` section currently lists the IOTAWizard/IOTAMenuWizard methods. Add a `Destroyed` override. Change:
```pascal
    // IOTAWizard
    function  GetIDString : string;
    function  GetName     : string;
    function  GetState    : TWizardState;
    procedure Execute;
    // IOTAMenuWizard
    function  GetMenuText : string;
  end;
```
to:
```pascal
    // IOTAWizard
    function  GetIDString : string;
    function  GetName     : string;
    function  GetState    : TWizardState;
    procedure Execute;
    // IOTANotifier (via TNotifierObject) -- primary teardown hook
    procedure Destroyed; override;
    // IOTAMenuWizard
    function  GetMenuText : string;
  end;
```

- [ ] **Step 3: Implement `TYadfotMenuWizard.Destroyed`**

Immediately after the `TYadfotMenuWizard.Execute` implementation (which ends `  DoFormatCurrentBuffer;` / `end;`), add:
```pascal
procedure TYadfotMenuWizard.Destroyed;
begin
  // Fires during IDE shutdown / package unload, BEFORE the BPL code segment is
  // dropped -- the primary hook that strips the options page so no IDE list
  // keeps a dangling interface into our vanishing vtable. Idempotent; safe
  // alongside the YADFOT.Options finalization (which runs later in shutdown).
  try UnregisterYADFOptions; except end;
end;
```

- [ ] **Step 4: Register the options page from `Register`**

In the `Register` procedure, after the keyboard-binding block, add the options registration. Change:
```pascal
  GWizardIndex:= (BorlandIDEServices as IOTAWizardServices).AddWizard(TYadfotMenuWizard.Create);
  KS:= BorlandIDEServices as IOTAKeyboardServices;
  if KS <> nil then
    GKeyboardBindingIndex:= KS.AddKeyboardBinding(TYadfotKeyboardBinding.Create);
end;
```
to:
```pascal
  GWizardIndex:= (BorlandIDEServices as IOTAWizardServices).AddWizard(TYadfotMenuWizard.Create);
  KS:= BorlandIDEServices as IOTAKeyboardServices;
  if KS <> nil then
    GKeyboardBindingIndex:= KS.AddKeyboardBinding(TYadfotKeyboardBinding.Create);
  // Add the Tools > Options > Third Party > YADF page. Tolerate failure so a
  // missing options service never aborts the whole registration.
  try RegisterYADFOptions; except end;
end;
```

- [ ] **Step 5: Do NOT commit yet** — build gate is Task 4.

---

### Task 3: Add `YADFOT.Options` to the `.dpk` `contains` clause and the `.dproj` reference list

**Files:**
- Modify: `c:\Projects\YADF\YADFOT.dpk` (`contains` clause, lines 38-45)
- Modify: `c:\Projects\YADF\YADFOT.dproj` (`<DCCReference>` list)

**Interfaces:** none (build-graph plumbing).

- [ ] **Step 1: Add the unit to `YADFOT.dpk`'s `contains` clause**

Change:
```
contains
  YADFOT.Wizard in 'YADFOT.Wizard.pas',
  YADF.Tokens in 'YADF.Tokens.pas',
```
to:
```
contains
  YADFOT.Wizard in 'YADFOT.Wizard.pas',
  YADFOT.Options in 'YADFOT.Options.pas',
  YADF.Tokens in 'YADF.Tokens.pas',
```
(The `contains` clause is what the package build actually compiles; a unit only in the `.dproj` reference list may be silently skipped — porting doc section 6.)

- [ ] **Step 2: Add the matching `<DCCReference>` to `YADFOT.dproj`**

Find the line `        <DCCReference Include="YADFOT.Wizard.pas"/>` and add the new reference right after it:
```xml
        <DCCReference Include="YADFOT.Wizard.pas"/>
        <DCCReference Include="YADFOT.Options.pas"/>
```

- [ ] **Step 3: Do NOT commit yet** — build gate is Task 4.

---

### Task 4: Build the Win32 Debug BPL and verify a clean compile

**Files:**
- Create (scratch, not committed): `C:\TEMP\claude\c--Projects-YADF\<session>\scratchpad\build_yadfot_debug.bat`

**Interfaces:** none. This is the primary automated verification gate for Tasks 1-3.

- [ ] **Step 1: Write the wrapper build batch** (per `delphi-build` skill)

Write to the scratchpad:
```bat
@echo off
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
cd /d "c:\Projects\YADF"
msbuild /t:Build /p:Config=Debug /p:Platform=Win32 /v:normal YADFOT.dproj
echo BUILD_EXITCODE=%ERRORLEVEL%
```

- [ ] **Step 2: Run it from PowerShell with output redirected** (close the IDE first if it has the BPL loaded/locked)

```powershell
$log = "C:\TEMP\claude\c--Projects-YADF\<session>\scratchpad\yadfot_debug_build.log"
Start-Process -FilePath "C:\TEMP\claude\c--Projects-YADF\<session>\scratchpad\build_yadfot_debug.bat" -Wait -NoNewWindow -RedirectStandardOutput $log -RedirectStandardError "$log.err"
```

- [ ] **Step 3: Read the log and confirm success**

```powershell
Select-String -Path $log -Pattern "BUILD_EXITCODE=","[dcc] (Error|Fatal)","\.bpl" | ForEach-Object { $_.Line }
```
Expected: `BUILD_EXITCODE=0`, NO `[dcc] Error`/`[dcc] Fatal` lines, and a `YADFOT.bpl` produced under `Win32\Debug\EXE`. If the build fails: read the `[dcc] Error` line, fix the offending unit (common: missing `uses` entry, a `}` inside a `{ }` comment closing it early, `finalization` before `initialization`), and re-run Step 2. Do not proceed until green.

- [ ] **Step 4: Confirm the Debug BPL exists at the IDE-loaded path**

```powershell
Get-Item "c:\Projects\YADF\Win32\Debug\EXE\YADFOT.bpl" | Select-Object FullName, Length, LastWriteTime
```
Expected: the file exists with a LastWriteTime from this build.

- [ ] **Step 5: Commit the implementation** (only now that the build is green)

Use the YADF git workflow (`.private\GITPush.bat` commits + pushes local + remote):
```bash
cd c:\Projects\YADF && .private\GITPush.bat "feat(ide): native Tools>Options>Third Party>YADF page (YADFOT.Options), remove-on-uninstall via wizard Destroyed"
```
(Do NOT commit `YADFOT.res` if it shows dirty after the build — it is always dirty and must never be committed; see the project memory. `git add -A` inside GITPush may stage it — if the script uses `-A`, unstage `YADFOT.res` first: `git reset YADFOT.res`.)

---

### Task 5: Update CHANGELOG.md + README.md and report live in-IDE verification steps

**Files:**
- Modify: `c:\Projects\YADF\CHANGELOG.md` (top / Unreleased section)
- Modify: `c:\Projects\YADF\README.md` (the YADFOT / IDE-integration section — locate it first)

**Interfaces:** none (docs).

- [ ] **Step 1: Add a CHANGELOG entry**

Read the current top of `CHANGELOG.md`, then add a line under the appropriate Unreleased/next-version heading, matching the file's existing style, e.g.:
```
- YADFOT: added a native **Tools > Options > Third Party > YADF** page that edits
  the shared %APPDATA%\YADF\yadf.ini through the same OptionTable as YADFSetup.
  Registered on package load and removed cleanly on uninstall (wizard Destroyed +
  unit finalization).
```

- [ ] **Step 2: Add a README note**

Locate the YADFOT/IDE-integration section in `README.md` (grep for `YADFOT` / `Install Packages` / `Ctrl+Shift+Alt+F`). Add a short paragraph noting the new Options page and that it round-trips the same `yadf.ini` as YADFSetup. Match surrounding style; keep `@RomanYankovsky` mentions in plain-link form per project convention.

- [ ] **Step 3: Commit the docs**

```bash
cd c:\Projects\YADF && .private\GITPush.bat "docs: note the new YADFOT Tools>Options page in CHANGELOG + README"
```

- [ ] **Step 4: Report the manual in-IDE verification checklist to the user**

The Debug BPL builds clean, but OTA UI cannot be verified headlessly. Tell the user to perform, in a fresh IDE session:
  1. `Tools > Options` shows a `Third Party > YADF` node with the grouped controls.
  2. Edit a value, click OK; open YADFSetup and confirm the change round-tripped through `yadf.ini`.
  3. `Component > Install Packages`, uncheck YADFOT -> confirm NO orphan YADF node in Tools>Options and no AV (also check on File > Exit).
  4. Re-check YADFOT -> confirm the page comes back.
State clearly that this manual step is the ONLY real acceptance test for the feature, and that publishing should wait until it passes.

---

## Self-Review

**Spec coverage:** Every spec section maps to a task — new unit (page class + generic frame + register/unregister + finalization) = Task 1; wizard wiring (uses/Destroyed/Register) = Task 2; `.dpk` + `.dproj` = Task 3; Win32 Debug build + clean-compile gate = Task 4; CHANGELOG/README + manual verification report = Task 5. INI target (`SharedAppDataIniPath`), commit-on-OK, single-page, read-modify-write Save, teardown contract, and the ASCII/CRLF + `.dpk` gotchas are all present.

**Placeholder scan:** No TBD/TODO/"add error handling"/"similar to". The only `<session>` tokens are literal scratchpad-path placeholders the executor substitutes with the real session dir from the environment; the build code and unit are complete.

**Type consistency:** `RegisterYADFOptions`/`UnregisterYADFOptions` (Task 1 interface) are the exact names consumed in Task 2. `TYadfOptionsFrame`/`TYadfOptionsPage` used consistently. `OptionTable`/`TOptInfo`/`okBool..okEnum`/`LoadOptionsFromIni`/`SaveOptionsToIni`/`EnsureIniExists`/`SharedAppDataIniPath` match the verified `YADF.Options.pas` signatures. `INTAAddInOptions`/`INTAEnvironmentOptionsServices`/`TCustomFrameClass` are the real ToolsAPI names.
