# YADFOT IDE Options page -- Profiles panel (F/R)

**Date:** 2026-07-08
**Status:** Approved (brainstorming complete)
**Target release:** 1.0.9.0
**Unit touched:** `YADFOT.Options.pas` (only)

## Problem

Since 1.0.8.0, config resolution is profile-based: `%APPDATA%\YADF\profiles.ini`
names the **F** profile (CLI default + `Ctrl+Shift+Alt+F`) and optional **R**
profile (`Ctrl+Shift+Alt+R`). YADFSetup.exe has a full **Profiles** panel to
manage this -- list all `*.ini`, badge which is F/R, click to switch which one
you edit, assign F/R, unassign, and create new profiles.

The **IDE Options page** (`Tools > Options > Third Party > YADF`) has **no
profiles UI at all**. It silently edits a single unnamed INI (the F profile).
A user cannot see which profile is active, edit the R profile, switch profiles,
or assign F/R from inside the IDE. This spec adds full YADFSetup parity to the
IDE page.

## Goal

Bring YADFSetup's complete Profiles capability into the IDE Options frame so the
page can fully replace the need to open YADFSetup for profile management.

## Non-goals

- No change to the formatting engine (byte-identical output; golden net 79/79).
- No change to how the CLI or the F/R shortcuts resolve profiles (that shipped
  in 1.0.8.0).
- No change to YADFSetup.exe.

## Design

All changes live in `YADFOT.Options.pas`, in `TYadfOptionsFrame`. Everything
reuses the existing shared primitives in `YADF.Options` (the same ones YADFSetup
uses): `LoadProfiles`, `SaveProfiles`, `ProfilesDir`, `ResolveProfileIniPath`,
`EnsureIniExists`, `SaveOptionsToIni`, `LoadOptionsFromIni`,
`SharedAppDataIniPath`. No new engine logic.

### Layout

A compact **Profiles group** at the TOP of the existing left options column
(above the scrolling option controls). The Source|Result preview on the right is
unchanged.

```
+-------------------------------------------------------------+
| Profiles                    |                               |
|  [F]  yadf.ini              |   Source     |    Result      |
|  [R]  yadf-D10-Test.ini     |              |                |
|       yadf-web.ini          |  (editable)  |  (formatted)   |
|  [Set F][Set R][Unassign][New...]          |                |
|-----------------------------|              |                |
| Options (scrolls)           |              |                |
|  MaxLen   [180]             |              |                |
|  Indent   [2]               |              |                |
|  [x] ReflowLines            |              |                |
|  ...                        |              |                |
+-------------------------------------------------------------+
```

Implementation note: the left column is currently a single `TScrollBox`
(`FScroll`) holding the option group-boxes. The Profiles group is placed in a
NON-scrolling `TPanel` docked `alTop` on the left side, ABOVE `FScroll`, so the
profiles stay visible while the options scroll. (`FScroll` moves from
`alLeft`-on-Self to `alClient`-in-a-left-host, or the profiles panel is given a
fixed height and the scrollbox `alClient` under it within the existing left
region. Chosen approach: a left host `TPanel` (`alLeft`, width 360) containing
the Profiles panel (`alTop`) + `FScroll` (`alClient`).)

### New fields (TYadfOptionsFrame)

- `FProfiles    : TYadfProfiles;`   -- current F/R mapping (from profiles.ini)
- `FProfileFiles: TArray<string>;`  -- file names index-aligned to the list rows
- `FCurrentIni  : string;`          -- full path of the profile being edited now
- `FProfileList : TListBox;`        -- the profiles list control
- (buttons are local to BuildProfilePanel; handlers reference the list)

### New methods

- `BuildProfilePanel` -- code-builds the Profiles group (label, `TListBox`, four
  `TButton`s), in the same code-built style as `BuildControls`.
- `RefreshProfileList` -- ports YADFSetup.RefreshProfileList: enumerate
  `ProfilesDir\*.ini` (skip `profiles.ini`), badge `[F]`/`[R]`/blank, rebuild
  `FProfileFiles`, and select the row matching `FCurrentIni`.
- `SwitchEditTo(const AIniFile: string)` -- ports YADFSetup.SwitchEditTo but
  AUTO-SAVES the current profile's option values first (see persistence):
  ControlsToOptions + SaveOptionsToIni(FOpts, FCurrentIni), then set
  FCurrentIni := ResolveProfileIniPath(AIniFile), EnsureIniExists,
  FOpts := LoadOptionsFromIni(FCurrentIni), OptionsToControls, Reformat.

### New event handlers

- `ProfileListClick`  -- if the clicked row != current, `SwitchEditTo(that)`.
- `SetFClick`         -- FProfiles.F := selected; SaveProfiles; RefreshProfileList.
- `SetRClick`         -- FProfiles.R := selected; SaveProfiles; RefreshProfileList.
- `UnassignClick`     -- if selected is R -> R:=''; else if selected is F -> F:='yadf.ini' (F must always have a value, per YADFSetup); SaveProfiles; RefreshProfileList.
- `NewProfileClick`   -- InputQuery for a name; sanitise to `yadf-<name>.ini`;
  if exists offer to edit it, else seed with current values
  (ControlsToOptions + SaveOptionsToIni to the new path); then SwitchEditTo(new).

### Persistence model (as decided)

- **Profile actions save immediately** (assign F/R, unassign, new) -- independent
  of the dialog OK/Cancel, exactly like YADFSetup.
- **Switching profiles auto-saves** the current profile's option values first, so
  no edits are silently lost.
- **OK (`DialogClosed(Accepted=True)` -> `Save`)** writes `FCurrentIni`.
- **Cancel** discards unsaved option-VALUE edits to the current profile; profile
  assignments already persisted (they are live).

### Load / Save changes

- `IniPath` (private) is replaced by `FCurrentIni` state. On `Load`, initialise
  `FProfiles := LoadProfiles`, `FCurrentIni := ResolveProfileIniPath(FProfiles.F)`
  (fallback `SharedAppDataIniPath`), `EnsureIniExists(FCurrentIni)`, then load +
  `RefreshProfileList`.
- `Save` writes `FCurrentIni` (read-modify-write via LoadOptionsFromIni +
  ControlsToOptions + SaveOptionsToIni), then the **mirror-onto-yadf.ini runs
  ONLY when `FCurrentIni` is the F profile**. Refinement vs 1.0.8.0, where the
  mirror always ran: with profile switching, editing R must NOT clobber the
  standard `%APPDATA%\YADF\yadf.ini`. Rule:
  `if SameFileName(FCurrentIni, ResolveProfileIniPath(FProfiles.F))` -> mirror
  onto `SharedAppDataIniPath` (guarded self-copy skip, best-effort) else skip.

## Testing / verification

- Compile YADFOT Debug Win32 clean (IDE closed).
- Behavioral test (standalone console harness against temp files) covering the
  pure logic that is safe to extract: badge computation, unassign rule (F resets
  to 'yadf.ini', R clears), and the mirror-only-when-F rule (self-copy guard,
  F-file mirrors, R-file does NOT mirror).
- Golden-format net 79/79 (engine untouched; config pinned via --ini).
- Full Release build stamps 1.0.9.0 on all three artifacts.

## Risks / notes

- The live-IDE-only traps from the Options-page recipe still apply
  (`.dfm`+`{$R}` for the code-built frame, teardown, etc.) but this change adds
  no new registration surface -- it only adds controls inside the existing frame,
  so those are already handled.
- `InputQuery` inside an IDE Options frame is a standard VCL modal dialog and is
  safe (YADFSetup uses it; the IDE hosts VCL dialogs fine).
- The list uses BUTTONS (not F/R/Del keypress) to avoid the IDE swallowing keys
  and for discoverability.
