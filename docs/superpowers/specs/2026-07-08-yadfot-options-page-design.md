# Design: Native Tools > Options page for YADFOT

Status: approved, ready for implementation plan. Ports the recipe in
`docs/PORT-tools-options-page.md` (distilled from drag-lint's battle-tested
"Batch B") into YADF. The porting doc is the reference; this spec records the
concrete decisions made for YADF and the exact surface to build.

## Goal

Add a native `Tools > Options > Third Party > YADF` page to the YADFOT IDE
wizard so YADF's formatting settings are editable in-IDE without launching the
standalone `YADFSetup.exe`. The page reuses YADF's existing settings store
(`yadf.ini` via `YADF.Options.pas`), so YADFSetup, YADFOT, and the CLI all
read/write the SAME data -- no new schema, no duplication.

Both editors stay: YADFSetup (standalone Win32 GUI) and the new IDE Options page
are two editors over the same `yadf.ini`, both going through `YADF.Options.pas`'s
single `OptionTable` descriptor. Neither supersedes the other.

## Decisions (locked)

1. **Single generic page**, not a multi-page split. One `Third Party > YADF`
   page iterates `OptionTable`, grouping by `TOptInfo.Group` into `TGroupBox`es
   inside a scrolling host, one control per row keyed by `Kind`. This mirrors
   YADFSetup's proven `BuildOptionControls`/`OptionsToControls`/`ControlsToOptions`
   triple (`uYADFSetupMain.pas` lines 127-266) -- the page structure is
   deliberately very similar to YADFSetup so the two editors look and behave
   alike. Zero per-field code; the page auto-syncs whenever a field is added to
   `TYadfOptions`/`OptionTable`.
2. **INI target = shared `%APPDATA%\YADF\yadf.ini`** (`SharedAppDataIniPath`).
   The same default file YADFSetup edits and tier-4 of the wizard's four-tier
   resolution. Simple "edits the shared/default profile" semantics; project- and
   source-local overrides remain a per-buffer concern the Options page does not
   represent. Profile-awareness (edit whichever INI F is bound to) is a possible
   later enhancement, explicitly out of scope here.
3. **Single new unit `YADFOT.Options.pas`** holding the options-page class, the
   generic frame, `Register`/`Unregister`, and the `initialization`/`finalization`
   block. Self-contained; one file to add to the `.dpk`.
4. **Commit on OK** (IDE convention). `DialogClosed(Accepted=True)` writes the
   controls back; Cancel discards. (YADFSetup's live per-change autosave is a
   standalone-GUI idiom; the IDE Options dialog conventionally commits on OK, and
   this is what the drag-lint reference does.) The two editors still converge on
   the same file -- the only difference is WHEN the write happens.

## New unit: `YADFOT.Options.pas`

### `TYadfOptionsPage = class(TInterfacedObject, INTAAddInOptions)`

Parameterized `(ACaption, AFrameClass)` per the porting doc (used once, but this
keeps a later N-page split a one-line change). Implements the 8 `INTAAddInOptions`
methods exactly as `TDragLintOptionsPage` (`DragLint.Plugin.Options.pas` 30-105):

- `GetArea: string` -> `''` (empty area => "Third Party" branch).
- `GetCaption: string` -> `FCaption` (`'YADF'` for the single page).
- `GetFrameClass: TCustomFrameClass` -> `FFrameClass`.
- `FrameCreated(AFrame)` -> cast to `TYadfOptionsFrame`, call `.Load`.
- `DialogClosed(Accepted)` -> if `Accepted and Assigned(FFrame)` call `.Save`;
  nil the frame ref either way (IDE may destroy/recreate the frame).
- `ValidateContents` -> `True`. `GetHelpContext` -> `0`.
  `IncludeInIDEInsight` -> `True`.

### `TYadfOptionsFrame = class(TFrame)`

A single generic frame, controls code-built (no `.dfm`, pure ASCII). Public
`Load`/`Save`; private `FOpts: TYadfOptions`, `FControls: array of TControl`
(index-aligned to `OptionTable`), `FUpdating: Boolean`.

- `BuildControls` (from constructor): adapts YADFSetup's `BuildOptionControls`.
  Iterate `OptionTable`; on a new `Group` create a `TGroupBox`; per row create
  `TCheckBox` (`okBool`) / `TSpinEdit` (`okInt`) / `TEdit` (`okString`) /
  `TComboBox` csDropDownList with `ANSI`/`UTF-8`/`UTF-16` (`okEnum`); set
  `Hint`/`ShowHint` from `TOptInfo.Hint`; store in `FControls[i]`. The frame owns
  a scrolling host (`TScrollBox`) sized so the whole option set scrolls, exactly
  like YADFSetup's `sbSettings`.
- `OptionsToControls` / `ControlsToOptions`: the same `FUpdating`-guarded
  push/pull as YADFSetup (setting `Checked`/`Value`/`Text`/`ItemIndex`).
- `Load`: `EnsureIniExists(P)` then `FOpts := LoadOptionsFromIni(P)` then
  `OptionsToControls`, where `P = SharedAppDataIniPath`.
- `Save`: read-modify-write shape. Re-read the record fresh
  (`FOpts := LoadOptionsFromIni(P)`), then `ControlsToOptions` (which writes the
  live control values onto `FOpts`, exactly as in YADFSetup), then
  `SaveOptionsToIni(FOpts, P)`. Re-reading first means any field NOT surfaced as
  a control (none today, but a guard for the future) survives; for the single
  page this is equivalent to writing the current `FOpts`, but keeping the
  read-modify-write shape costs nothing and makes a future page split safe.
  `ControlsToOptions` keeps YADFSetup's exact signature (operating on `FOpts`),
  so no `var`-target refactor is needed.

No `OnClick`/`OnChange` live-preview handlers are wired (unlike YADFSetup, which
autosaves + reformats on change). The Options page is inert until OK.

### Register / Unregister / teardown

```pascal
var GOptions: array of INTAAddInOptions;

procedure RegisterYADFOptions;   // Supports(...INTAEnvironmentOptionsServices);
                                 // Add('YADF', TYadfOptionsFrame)
procedure UnregisterYADFOptions; // guard Length=0; UnregisterAddInOptions each;
                                 // SetLength(...,0)  -- idempotent
```

Both idempotent (guard + clear). `initialization` empty; `finalization` calls
`UnregisterYADFOptions` as the SECONDARY teardown net.

## Wiring: `YADFOT.Wizard.pas`

1. Add `YADFOT.Options` to the implementation `uses` clause.
2. Add `procedure Destroyed; override;` to `TYadfotMenuWizard`'s public section
   (it currently inherits `TNotifierObject`'s no-op). Implement:
   ```pascal
   procedure TYadfotMenuWizard.Destroyed;
   begin
     try UnregisterYADFOptions; except end;
   end;
   ```
   This is the PRIMARY teardown hook: `Destroyed` fires during IDE shutdown /
   package unload BEFORE the BPL code segment is dropped, so no IDE list keeps a
   dangling `INTAAddInOptions` into a vanished vtable. This is the load-bearing
   requirement the user emphasized: remove the page cleanly on uninstall.
3. Add `try RegisterYADFOptions; except end;` inside the existing `Register`
   procedure -- so the page appears when the package is (re)installed.

The wizard's existing `finalization` (wizard slot + keyboard binding handback)
is left as-is; `YADFOT.Options`'s own `finalization` handles the options
teardown net, colocated with its `Register` per the porting doc's recommendation.

## `.dpk`: `YADFOT.dpk`

Add `YADFOT.Options in 'YADFOT.Options.pas',` to the `contains` clause (NOT just
the `.dproj` reference list -- a unit only in the `.dproj` may be silently
skipped by a package build). Confirm `designide` is already in `requires` (it is)
-- `INTAAddInOptions`/`TCustomFrameClass` come from `ToolsAPI`, and `TFrame`
from `Vcl.Forms`.

Pascal gotchas to avoid in the fresh unit (per porting doc section 6):
`initialization` must precede `finalization`; `{ }` block comments do not nest;
add `System.SysUtils` (`Supports`) / `Vcl.Forms` / `Vcl.Controls` / `Vcl.StdCtrls`
/ `Vcl.ExtCtrls` / `Vcl.Samples.Spin` / `ToolsAPI` / `YADF.Options` to `uses`.

## Build + verification

- Build the Win32 **Debug** configuration of `YADFOT.dproj` (the IDE loads the
  Debug BPL). Close the IDE first (running IDE locks the BPL). Use the project's
  rsvars+msbuild wrapper-batch recipe (`delphi-build` skill); confirm
  `BUILD_EXITCODE=0` and no `[dcc] Error`. A clean build is necessary but NOT
  sufficient.
- **Live in-IDE verification (manual, cannot be automated -- OTA UI is not
  headless-testable), for the user to perform:**
  1. Reopen the IDE; `Tools > Options` shows a `Third Party > YADF` node with the
     expected grouped controls.
  2. Edit a value, click OK, reopen YADFSetup -> confirm the change round-tripped
     through `yadf.ini`.
  3. Uncheck YADFOT in `Component > Install Packages` -> confirm NO orphan YADF
     node and no AV.
  4. Re-check the package -> confirm the page comes back.

## Post-implementation corrections (bugs found in live IDE test)

Two defects the "clean compile" gate did NOT catch (both are OTA/package-level,
only reproducible by loading the BPL in a real IDE) were found and fixed:

1. **Package-load collision (`vclsmp`).** The frame's `TSpinEdit` comes from
   `Vcl.Samples.Spin`, owned by `vclsmp370.bpl`. `YADFOT.dpk` did not `require`
   it, so the linker statically CONTAINED that unit in `YADFOT.bpl` (build warned
   `W1033`), and the IDE nagged "Cannot load package ... also contained in
   VclSmp370" ~40x. Fix: add `vclsmp` to `requires` + `vclsmp.dcp` to the
   `.dproj`. Lesson: for a design-time package, treat `W1033` as an error.
2. **`EResNotFound` on Options-page open ("TYadfOptionsFrame not found").**
   `TCustomFrame.Create` always streams a per-class `.dfm` resource via
   `InitInheritedComponent`; a code-built frame with NO `.dfm` still raises. Fix:
   ship a minimal `YADFOT.Options.dfm` (bare root object) + `{$R *.dfm}` +
   `<Form>/<FormType>/<DesignClass>` in the `.dproj`. Lesson: "code-built frame,
   no .dfm" is WRONG; the frame always needs a streamable root resource.

Both corrections are folded back into `docs/PORT-tools-options-page.md` (sections
2 and 6) so the reusable recipe no longer misleads.

## Out of scope

- Profile-aware editing (edit the F-bound INI). Ship shared-file first.
- Multi-page split. The parameterized page class keeps it a later one-liner.
- Live preview / autosave in the Options page (that stays YADFSetup's idiom).

## Non-goals confirmation

The porting doc says a planning/verify-only session must NOT commit the
implementation. This spec IS committed; the implementation is a separate step in
the same session and will be committed + pushed (per the YADF git workflow) once
the Debug BPL builds clean, with the live in-IDE verification flagged for the
user. Publishing happens after everything is done, per the user.
