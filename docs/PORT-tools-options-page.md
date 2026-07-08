# Port: Tools > Options page for YADFOT (+ clean teardown)

Status: implementation-ready recipe, not yet implemented. Written by a sibling-repo
session that ported this exact feature into drag-lint ("Batch B"), battle-tested there,
and is now distilling it for YADF. Items you must confirm/adjust in the YADF codebase
are marked **VERIFY IN YADF**.

Goal: add a native `Tools > Options > Third Party > YADF` page (or a small set of
nested pages) to the YADFOT IDE wizard, so YADF's formatting settings are editable
in-IDE without launching the standalone YADFSetup.exe. Reuse YADF's existing settings
store (`yadf.ini` via `YADF.Options.pas`) so YADFSetup, YADFOT, and the CLI all read/
write the SAME data -- no new settings schema, no duplication.

Reference implementation (read these for exact patterns, they are cited by name
throughout): `C:\Projects\Delphi-RAG-lint\src\delphi-plugin\DragLint.Plugin.Options.pas`,
`DragLint.Plugin.OptionsFrames.pas`, `DragLint.Plugin.Wizard.pas`.


## 1. The INTAAddInOptions page object

A Tools > Options page is any object implementing `INTAAddInOptions` (declared in
`ToolsAPI`), registered via `INTAEnvironmentOptionsServices.RegisterAddInOptions`.

Interface methods and what to return:

- `GetArea: string` -> return `''`. Empty area is what puts the page under the
  "Third Party" branch in the left tree; this is Embarcadero's documented convention.
  There is no reliable way to land a page under a built-in branch (e.g.
  Editor > Language) by guessing a magic area string -- do not attempt it.
- `GetCaption: string` -> the page's caption. A DOT in the caption NESTS pages under a
  parent node: `GetArea = ''` + `GetCaption = 'YADF.Formatting'` renders as
  `Third Party / YADF / Formatting` in the tree. For a single page, just return
  `'YADF'`.
- `GetFrameClass: TCustomFrameClass` -> the VCL `TFrame` subclass that renders this
  page's controls.
- `FrameCreated(AFrame: TCustomFrame)` -> the IDE just constructed the frame; cast it
  to your frame class and call its `Load` method (populate controls from settings).
- `DialogClosed(Accepted: Boolean)` -> if `Accepted`, call the frame's `Save` (write
  controls back to the settings store); then clear/nil your frame reference either
  way, because the IDE may destroy and recreate the frame between dialog opens.
- `ValidateContents: Boolean` -> `True` (no validation gate).
- `GetHelpContext: Integer` -> `0`.
- `IncludeInIDEInsight: Boolean` -> `True`.

Reference: `TDragLintOptionsPage` in `DragLint.Plugin.Options.pas` (lines 30-105)
implements exactly this, parameterized by `(ACaption, AFrameClass)` so ONE class
serves all pages (see section 3).


## 2. The frame

A `TFrame` subclass with a `Load` (settings -> controls) and `Save` (controls ->
settings) pair. Two viable approaches -- pick one for YADF:

**Option A -- code-built controls WITH a minimal .dfm (drag-lint's convention).**
The frame builds `TGroupBox`/`TCheckBox`/`TEdit`/`TSpinEdit` controls in a
`BuildControls` method called from the constructor, using small helper functions
(`NewGroup`, `NewLabel`, `NewEdit`, `NewCheck` -- see `DLNewGroup`/`DLNewLabel`/
`DLNewEdit`/`DLNewCheck` in `DragLint.Plugin.OptionsFrames.pas` lines 195-241).
It is trivial to drive from a generic table (see section 7 -- a strong fit for
YADF because `YADF.Options.OptionTable` already IS such a table).

**LOAD-BEARING GOTCHA (this bit the first YADF attempt -- do NOT skip):** a
code-built frame STILL needs a minimal `.dfm`. `TCustomFrame.Create` always
streams a per-class resource via `InitInheritedComponent(Self, TFrame)` and
raises `EResNotFound` ("<FrameClassName> not found") when the ancestor walk finds
no resource for any class in the chain. Frames, unlike forms, have NO `CreateNew`
to skip streaming, so "code-built, no .dfm" does NOT compile-and-run -- it builds
clean and then throws at Options-page-open time. Ship a bare `.dfm` next to the
unit declaring only the frame root object:

```
object YadfOptionsFrame: TYadfOptionsFrame
  Left = 0
  Top = 0
  Width = 520
  Height = 460
end
```

and add `{$R *.dfm}` in the unit's implementation section. The real controls stay
code-built in `BuildControls`; the `.dfm` only supplies the streamable root. In
the `.dproj`, the unit's `<DCCReference>` must carry `<Form>YadfOptionsFrame</Form>`
+ `<FormType>dfm</FormType>` + `<DesignClass>TFrame</DesignClass>` (the `<Form>`
value is the root object's INSTANCE name from the `.dfm`, not the class name). The
`.dfm` is strict ASCII/CRLF like every other resource here. See
`DragLint.Plugin.OptionsFrames.dfm` (87 bytes) and its `{$R *.dfm}` +
`.dproj` block for the exact working reference.

**Option B -- a .dfm-backed frame**, laid out visually in the Form Designer like
`uYADFSetupMain.dfm`. Simpler to eyeball visually, but the frame becomes a second
place (besides YADFSetup's own `.dfm`) that must be kept in sync if a field is added,
and the .dfm is a binary/text resource outside the plain-ASCII-Pascal convention.

Recommendation for YADF: **Option A**, specifically as a single generic frame driven
by `OptionTable` (see section 7) -- this avoids hand-writing ~35 near-duplicate
control declarations and keeps the page automatically in sync whenever a field is
added to `TYadfOptions`/`OptionTable` in `YADF.Options.pas`. A single generic page is
also simpler than the drag-lint 4-page split because YADF's settings do not yet have
the same combinatorial size (drag-lint had ~26 fields across register/indexer/linter/
editor; YADF has ~35 fields but they are already the SAME uniform shape, one row per
option, no heterogeneous CLI-only surface). If a future YADF session prefers grouping
by `OptInfo.Group` into separate Options sub-pages (mirroring `BuildOptionControls`'s
grouping), section 3 explains how to extend to N pages later -- the recipe is the
same either way.


## 3. Multi-page option (extend to N pages later if desired)

Register N distinct `INTAAddInOptions` instances with dotted captions (e.g.
`YADF.Formatting`, `YADF.Alignment`, `YADF.FileOutput`), each carrying its OWN frame
class. Parameterize ONE options-page class with `(caption, frameclass)` fields rather
than writing N near-duplicate classes -- see `TDragLintOptionsPage.Create` and the
`Add` local procedure inside `RegisterDragLintOptions` (`DragLint.Plugin.Options.pas`
lines 112-131) for the exact pattern:

```pascal
procedure RegisterDragLintOptions;
var
  Svc: INTAEnvironmentOptionsServices;
  procedure Add(const ACap: string; AFC: TCustomFrameClass);
  var O: INTAAddInOptions;
  begin
    O:= TDragLintOptionsPage.Create(ACap, AFC);
    Svc.RegisterAddInOptions(O);
    GOptions:= GOptions + [O];
  end;
begin
  if not Supports(BorlandIDEServices, INTAEnvironmentOptionsServices, Svc) then Exit;
  Add('drag-lint.General', TDLGeneralOptionsFrame);
  Add('drag-lint.Indexer', TDLIndexerOptionsFrame);
  ...
end;
```

**CRITICAL bug to avoid:** each instance must carry its OWN frame class. A common
mistake is registering the same frame class N times, so every page in the tree shows
identical controls.

**If multiple pages edit ONE settings record** (which is exactly YADF's situation --
one `TYadfOptions` record, one `yadf.ini`), use a READ-MODIFY-WRITE `Save` on every
page: each page's `Save` re-reads the whole settings record fresh
(`LoadOptionsFromIni`), applies only the fields that page owns, then writes the whole
record back (`SaveOptionsToIni`). This is what stops page A's `Save` from clobbering
page B's already-edited-but-not-yet-saved fields when the user has both pages open in
the same Options dialog session. See `TDLPageFrame.Save` (`DragLint.Plugin.
OptionsFrames.pas` lines 184-191):

```pascal
procedure TDLPageFrame.Save;
var S: TDragLintSettings;
begin
  S:= LoadSettings;      { re-read: do not clobber other pages' fields }
  SaveControls(S);
  SaveSettings(S);
end;
```

For a single YADF page this read-modify-write concern mostly disappears (there is
only one page, so there is nothing else to clobber) -- but keep the same shape
anyway (`LoadOptionsFromIni` then apply then `SaveOptionsToIni`) so it costs nothing
to split into multiple pages later.


## 4. The register/unregister lifecycle

**VERIFY IN YADF -- exact wiring location:** `C:\Projects\YADF\YADFOT.Wizard.pas`.
This unit's `Register` procedure (lines 632-640 as read) currently does:

```pascal
procedure Register;
var KS: IOTAKeyboardServices;
begin
  GWizardIndex:= (BorlandIDEServices as IOTAWizardServices).AddWizard(TYadfotMenuWizard.Create);
  KS:= BorlandIDEServices as IOTAKeyboardServices;
  if KS <> nil then
    GKeyboardBindingIndex:= KS.AddKeyboardBinding(TYadfotKeyboardBinding.Create);
end;
```

Add a `RegisterYADFOptions;` call into this `Register` procedure (new unit --
suggest `YADFOT.Options.pas`, see section 6 for the new-unit/.dpk requirement).

Recipe (mirrors `DragLint.Plugin.Options.pas` lines 107-142):

```pascal
var
  GOptions: array of INTAAddInOptions;   { or a single INTAAddInOptions if 1 page }

procedure RegisterYADFOptions;
var
  Svc: INTAEnvironmentOptionsServices;
  procedure Add(const ACap: string; AFC: TCustomFrameClass);
  var O: INTAAddInOptions;
  begin
    O:= TYadfOptionsPage.Create(ACap, AFC);
    Svc.RegisterAddInOptions(O);
    GOptions:= GOptions + [O];
  end;
begin
  if not Supports(BorlandIDEServices, INTAEnvironmentOptionsServices, Svc) then Exit;
  Add('YADF', TYadfOptionsFrame);   { single page; add more Add(...) calls to split later }
end;

procedure UnregisterYADFOptions;
var
  Svc: INTAEnvironmentOptionsServices;
  O  : INTAAddInOptions;
begin
  if Length(GOptions) = 0 then Exit;
  if Supports(BorlandIDEServices, INTAEnvironmentOptionsServices, Svc) then
    for O in GOptions do try Svc.UnregisterAddInOptions(O); except end;
  SetLength(GOptions, 0);
end;
```

Both procedures are idempotent by construction (`Length(GOptions) = 0` guard on
unregister; `SetLength(..., 0)` clears the ref array so a second call is a safe
no-op).


## 5. THE TEARDOWN CONTRACT (load-bearing -- read this section twice)

This is the single most important part of the port, and the exact bug class that
drag-lint's Batch B FIXED: `UnregisterDragLintOptions` was IMPLEMENTED but never
actually WIRED into the teardown path used at the time -- leaving a dangling
`INTAAddInOptions` interface registered after package unload. A dangling interface
into a vanished BPL code segment/vtable is an AV waiting to happen (on File > Exit,
on the next editor paint, or on Options dialog open after the package is unloaded).

The rule, in two parts:

1. **Every OTA registration must have a matching unregister wired into the wizard's
   `Destroyed` method.** `Destroyed` is part of `IOTANotifier` (the ancestor
   interface of `IOTAWizard`); it fires during IDE shutdown / package unload, BEFORE
   the BPL's code segment is dropped -- this is the PRIMARY, reliable teardown hook.
   Unit `finalization` blocks run later in the same shutdown and are not guaranteed
   to run before every dependent structure is torn down, so `Destroyed` must do the
   real work.

2. **A unit `finalization` calling the same unregister function is a SECONDARY net**
   -- in case `Destroyed` is skipped (e.g. Register never ran, or some IDE teardown
   path does not call `Destroyed` on every registered wizard). Both call sites must
   be safe to invoke twice (idempotent via the guard+clear pattern above), because
   `Destroyed`-then-`finalization` is exactly a double-call in the normal shutdown
   sequence.

Reference: `DragLint.Plugin.Wizard.pas` lines 51-68 (`Destroyed`) and
`DragLint.Plugin.Options.pas` lines 144-149 (`finalization`):

```pascal
procedure TDragLintWizard.Destroyed;
begin
  { wizard.Destroyed fires during IDE shutdown / package unload, BEFORE the BPL
    code segment is dropped. Strip every notifier we ever handed to the IDE so
    no module / view / IDE list keeps a dangling interface pointer into our
    soon-to-vanish vtable. All are idempotent; safe to call here in addition to
    the unit finalizations (which run later in the same shutdown). }
  ...
  try UnregisterDragLintOptions; except end;
  ...
end;
```

```pascal
initialization
finalization
  UnregisterDragLintOptions;  { secondary net; Wizard.Destroyed is primary }
end.
```

### VERIFY IN YADF -- Destroyed does not exist yet

`YADFOT.Wizard.pas`'s `TYadfotMenuWizard` is declared as
`class(TNotifierObject, IOTAWizard, IOTAMenuWizard)` (line 53 as read). It inherits
`TNotifierObject`'s no-op `Destroyed`/`AfterSave`/`BeforeSave`/`Modified` and does NOT
currently override `Destroyed`. To wire the teardown contract:

- Add `procedure Destroyed; override;` to the `public` section of
  `TYadfotMenuWizard` (around line 58-62 as read, alongside the other `IOTAWizard`
  method declarations).
- Implement it near `TYadfotMenuWizard.Execute` (around line 575-578 as read):

```pascal
procedure TYadfotMenuWizard.Destroyed;
begin
  { Fires during IDE shutdown / package unload, BEFORE the BPL code segment is
    dropped. Idempotent; safe alongside the unit finalization below. }
  try UnregisterYADFOptions; except end;
end;
```

- Add `try RegisterYADFOptions; except end;` to `Register` in `YADFOT.Wizard.pas`
  (see section 4 above for exact call).
- Add the `finalization` secondary net either in the new `YADFOT.Options.pas` unit
  itself (matching drag-lint's convention -- the unregister lives with its own
  register, self-contained) -- this is the recommended placement, OR, if the YADF
  session prefers centralizing all teardown in one place, add a call from
  `YADFOT.Wizard.pas`'s own existing `finalization` block (lines 642-652 as read,
  which currently only handles `GWizardIndex`/`GKeyboardBindingIndex`). Either
  placement is safe as long as `UnregisterYADFOptions` is idempotent -- prefer
  colocating it with `RegisterYADFOptions` in `YADFOT.Options.pas` for the same
  reason drag-lint did (the register/unregister pair and their guard state live in
  one unit, not split across two).

**Live-verify in the IDE** (cannot be automated -- OTA UI is not headless-testable):
after unchecking YADFOT in Component/Install Packages, Tools > Options must show NO
orphan YADF node, and there must be no AV. Re-checking the package must restore the
page. This is the ONLY real verification for this feature; treat a clean BPL build as
necessary but not sufficient.


## 6. THE .dpk GOTCHA (must not be skipped)

**VERIFY IN YADF -- confirmed current `.dpk` contains clause**, from
`C:\Projects\YADF\YADFOT.dpk`:

```
contains
  YADFOT.Wizard in 'YADFOT.Wizard.pas',
  YADF.Tokens in 'YADF.Tokens.pas',
  YADF.Options in 'YADF.Options.pas',
  YADF.Groups in 'YADF.Groups.pas',
  YADF.Layout in 'YADF.Layout.pas',
  SimpleParser.Lexer in '..\DelphiAST\Source\SimpleParser\SimpleParser.Lexer.pas',
  SimpleParser.Lexer.Types in '..\DelphiAST\Source\SimpleParser\SimpleParser.Lexer.Types.pas';
```

A new unit added ONLY to the `.dproj`'s `<DCCReference>` list is NOT necessarily
compiled by a package build -- if nothing in the compiled graph references it, and
it is not in the `.dpk`'s `contains` clause, the compiler silently skips it. Its
compile errors then go UNDETECTED until something else pulls it into the build graph
(e.g. months later, when a different change finally `uses`-references it) -- at
which point the errors surface far from their real cause and look unrelated to
whatever triggered the build.

**RULE: add every new plugin unit (the options-page unit and the frame unit, if
split into two files) to the `.dpk` `contains` clause -- that is what actually gets
compiled into the BPL** -- not just the `.dproj` reference list. If using the RAD
Studio IDE's "Add to Project" on the `.dpk`, this normally happens automatically;
if hand-editing the `.dpk` text, do not forget this step.

Two related Pascal gotchas that bit drag-lint's new unit and are easy to miss in a
freshly-created unit:

- **`initialization` must precede `finalization`** when both appear in the same
  unit -- a bare `finalization` with no preceding `initialization` is a compile
  error. Add an empty `initialization` line if you only need `finalization`.
- **Block comments do not nest.** A literal `}` inside a `{ ... }` comment block
  closes the comment early, silently truncating a doc comment and potentially
  turning the rest of the "comment" into live code (or a syntax error). Watch for
  this if a comment mentions Pascal syntax examples containing `{`/`}`, or uses
  `{$IFDEF}`-style text inside prose.
- Also watch for a missing `System.SysUtils` (or similar) `uses` entry if the new
  unit calls `Supports`, `SameText`, string-conversion helpers, etc. -- these look
  like they "should" be available but are not implicitly pulled in, and the error
  again may not surface until the unit is actually compiled per the .dpk rule above.

**THE `requires` GOTCHA (this bit the first YADF attempt -- a package-load
collision, ~40 dialogs at IDE start).** If the frame uses a control whose unit
lives in a design-time package the wizard package does NOT already `require`, the
linker STATICALLY LINKS that unit INTO your BPL instead of importing it. At IDE
load, two loaded packages then claim the same unit and the IDE nags "Cannot load
package <YOU>. It contains unit '<Unit>', which is also contained in package
'<Other>'." per attempt. The build PREDICTS this with `W1033: Unit '<Unit>'
implicitly imported into package '<YOU>'` -- treat W1033 as an ERROR for a
design-time package (it is only harmless for a standalone .exe like YADFSetup,
which links everything and has no sibling package to collide with). Fix: add the
owning package to `requires` (and its `.dcp` to the `.dproj` `<DCCReference>`
list). The concrete case here: `TSpinEdit` lives in `Vcl.Samples.Spin` (owned by
`vclsmp370.bpl`), so `YADFOT.dpk` must `require vclsmp` and the `.dproj` must
reference `vclsmp.dcp`. The drag-lint reference package (`dclDragLintWizard.dpk`)
already lists `vclsmp` in `requires` for exactly this reason. To find the owning
package for any unit, note the `W1033` package name in the build log, or check
which `*.bpl` in the IDE `bin` dir exports the unit.


## 7. Wiring the frame to YADF's existing settings store

**VERIFY IN YADF -- confirmed exact API to reuse**, all in
`C:\Projects\YADF\YADF.Options.pas`:

- `TYadfOptions` (record, ~35 fields: `MaxLen`, `Indent`, `TabWidth`,
  `ReflowLines`, `LowercaseKeywords`, ... through `Backup`/`BackupDir`/`ResultDir`/
  `Encoding`/`Logging`) is the in-memory settings shape.
- `TOptInfo` (record) + `OptionTable: TArray<TOptInfo>` (function, built once,
  cached in a unit-level `GOptTable` var) is a GENERIC descriptor table: each row
  carries `Ident` (the INI key AND record field name), `Group` (UI grouping /
  template section header), `Caption` (GUI label), `Hint` (tooltip / help text),
  `Kind` (`okBool`/`okInt`/`okString`/`okEnum`), `AffectsPreview` (whether the field
  changes formatted output vs. is file/CLI-only), and a `GetVal`/`SetVal` closure
  pair (`TOptGetter`/`TOptSetter`, both `reference to function/procedure`) that
  read/write that one field on a `TYadfOptions` via `Variant`.
- `LoadOptionsFromIni(const APath: string): TYadfOptions` and
  `SaveOptionsToIni(const AOpts: TYadfOptions; const APath: string)` are the
  load/save entry points -- both already used by YADFSetup and the CLI. The Options
  page frame's `Load`/`Save` should call exactly these, on exactly the same
  `yadf.ini` path YADFOT already resolves.
- `EnsureIniExists(const APath: string): Boolean` materializes a fully-commented
  template if the file is missing -- call this before the first load so the page
  never opens against a nonexistent file.

**Because `OptionTable` is already fully generic** (`Group`/`Caption`/`Hint`/`Kind`/
`GetVal`/`SetVal` per field), the Options-page frame does NOT need ~35 hand-written
field-specific `LoadControls`/`SaveControls` clauses the way drag-lint's frames do
(drag-lint's `TDragLintSettings` has no such generic table, so each of its 4 frames
hand-lists its own subset of fields). Instead, YADF's frame can literally reuse the
same generic-loop pattern already proven in
`uYADFSetupMain.TfrmMain.BuildOptionControls` / `OptionsToControls` /
`ControlsToOptions` (`C:\Projects\YADF\uYADFSetupMain.pas` lines 127-266): iterate
`OptionTable`, create one control per row keyed by `Kind` (`TCheckBox` for `okBool`,
`TSpinEdit` for `okInt`, `TEdit` for `okString`, `TComboBox` for `okEnum`), and use
`T[i].GetVal(FOpts)` / `T[i].SetVal(FOpts, V)` to move data. This is the single
biggest simplification available to the YADF port versus the drag-lint reference
(which has no generic table to lean on) -- do not hand-write per-field code; drive it
from `OptionTable`.

**Which INI path does the Options-page frame load/save?** VERIFY IN YADF: YADFOT
already has a four-tier INI resolution order in `ResolveOptions`
(`YADFOT.Wizard.pas` lines 196-222: source-file-relative walk-up, then
active-project-relative walk-up, then legacy `%APPDATA%\YADFOT\yadf.ini`, then
shared `%APPDATA%\YADF\yadf.ini`). Decide (and document in code comments) which of
these the Options page edits:

- Simplest and most predictable for a global IDE settings page: always target the
  shared per-user file, `SharedAppDataIniPath` (`YADF.Options.pas` line 544-551,
  `%APPDATA%\YADF\yadf.ini`) -- the same file YADFSetup edits by default and the
  same one `AppDataIniPath` in `YADFOT.Wizard.pas` resolves at tier 4. This keeps
  the Options page's semantics simple: "edits the shared/default profile," while
  the buffer-format action's project/source-local walk-up (tiers 1-2) remains an
  IDE-only per-project override that the Options page does not need to represent.
- If YADF later wants the Options page to be profile-aware (edit whichever profile
  is bound to F or R), that is an enhancement on top of this recipe, not a
  prerequisite -- ship the shared-file version first.

Whichever path is chosen, the frame's `Load`/`Save` should call
`LoadOptionsFromIni(Path)` / `SaveOptionsToIni(Opts, Path)` -- never hand-roll INI
reads, and never duplicate `TYadfOptions`'s field list into a second schema.

### YADFSetup.dpr relationship

`YADFSetup.dpr` (-> `uYADFSetupMain.pas`) is YADF's standalone Win32 visual settings
editor; it already reads/writes the shared `yadf.ini` via the exact same
`LoadOptionsFromIni`/`SaveOptionsToIni`/`OptionTable` API described above. The new
IDE Options page becomes a SECOND editor over the SAME file using the SAME API --
there is no migration needed and no risk of drift, because both consumers go
through `YADF.Options.pas`'s single descriptor table. Do not attempt to have one
supersede the other; both stay, both hit the same `yadf.ini`.


## 8. Build + test

**VERIFY IN YADF -- Debug vs Release BPL gotcha:** `build_all.bat` only builds
Release. The IDE, however, loads YADFOT from `Win32\Debug\EXE\YADFOT.bpl` (VERIFY
IN YADF: confirm this exact path against the current `YADFOT.dproj`'s configured
output directories -- the path stated here is what a prior session already noted as
the gotcha, re-confirm it still holds). This means:

1. To test the new Options page in a real IDE session, rebuild the Win32 **Debug**
   configuration of `YADFOT.dproj` specifically -- `build_all.bat` alone is not
   sufficient and will leave the IDE running a stale BPL with no Options page.
2. Close the IDE BEFORE rebuilding (the running IDE has the BPL loaded/locked).
3. Use the project's standard Delphi build recipe (rsvars.bat + msbuild via a
   wrapper .bat, `Start-Process -Wait`, then read the log for
   `BUILD_EXITCODE=0` / no `[dcc] Error`) -- do not invoke the MCP build tool or a
   bare `cmd.exe /c build.bat` (both are known-broken invocation paths for this
   family of Delphi projects).
4. Reopen the IDE, confirm Tools > Options shows the new YADF node (Third Party
   branch) with the expected controls, edit a value, close with OK, reopen
   YADFSetup and confirm the change round-tripped through `yadf.ini`.
5. Uncheck YADFOT in Component > Install Packages -- confirm no orphan node, no AV.
   Re-check -- confirm the page comes back.


## 9. Port checklist

1. Decide single-page vs multi-page (default recommendation: single page,
   `OptionTable`-driven -- see section 2/7). Note the choice in a code comment.
2. Create `YADFOT.Options.pas` (new unit) containing:
   - `TYadfOptionsPage = class(TInterfacedObject, INTAAddInOptions)` per section 1,
     parameterized `(ACaption, AFrameClass)` per section 3 even if only used once.
   - `RegisterYADFOptions` / `UnregisterYADFOptions` per section 4, with the
     `GOptions` module var and idempotent guard.
   - `initialization` / `finalization` block per section 5 (finalization calls
     `UnregisterYADFOptions` as the secondary net).
3. Create the frame unit (can be the same unit as step 2, or split into
   `YADFOT.OptionsFrame.pas` mirroring drag-lint's `Options.pas` /
   `OptionsFrames.pas` split -- either is fine): a `TFrame` subclass with
   `Load`/`Save` built generically over `YADF.Options.OptionTable`, per section 7.
   Reuse `DLNewGroup`/`DLNewLabel`/`DLNewEdit`/`DLNewCheck`-style helpers (write
   YADF-local equivalents; do not import drag-lint's) -- and add an `okEnum`
   `TComboBox` helper as well (see `uYADFSetupMain.BuildOptionControls`'s `okEnum`
   branch for the pattern: fixed 3-item list `ANSI`/`UTF-8`/`UTF-16`, `csDropDownList`
   style).
4. In `YADFOT.Wizard.pas`:
   - Add `procedure Destroyed; override;` to `TYadfotMenuWizard`'s interface
     section and implement it to call `try UnregisterYADFOptions; except end;`
     (section 5).
   - Add `try RegisterYADFOptions; except end;` inside `Register` (section 4/5).
   - Add `YADFOT.Options` (or your chosen unit name) to the `uses` clause.
5. Add the new unit(s) to `YADFOT.dpk`'s `contains` clause (section 6) -- NOT just
   the `.dproj` reference list. Watch for the `initialization`-before-`finalization`
   rule and non-nesting `{ }` comments if writing fresh doc comments (section 6).
6. Rebuild Win32 **Debug** `YADFOT.dproj` with the IDE closed (section 8), using the
   project's standard rsvars+msbuild wrapper-batch recipe. Confirm
   `BUILD_EXITCODE=0`, no `[dcc] Error`.
7. Reopen the IDE and live-verify per section 8, step 4-5 (Options page renders and
   round-trips through `yadf.ini`; uninstall/reinstall the package cleanly with no
   AV and no orphan node).
8. (Not part of this doc's scope, but worth noting for the implementing session:)
   consider whether `CHANGELOG.md` / `README.md` need a line about the new IDE
   Options page once implemented and verified.

Do not commit any of this from a session that is only meant to plan/verify --
this document is the plan; a later session does the implementation and commits it.
