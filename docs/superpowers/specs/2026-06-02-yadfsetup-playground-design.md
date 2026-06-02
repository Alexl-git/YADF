# YADFSetup — Visual Settings Editor & Format Playground — Design

**Date:** 2026-06-02
**Status:** Approved (pending written-spec review)
**Author:** Alexander Liberov (with Claude Opus)
**Repo:** `C:\Projects\YADF`

---

## 1. Summary

Add a third shipping artifact, **`YADFSetup.exe`** — a VCL GUI that lets a user
load Pascal source, see it formatted live, and tune **every** YADF option
visually. Settings are persisted to the shared `yadf.ini` that `YADF.exe` (CLI)
and `YADFOT.bpl` (IDE wizard) already consume, so YADFSetup becomes the visual
front-end for the whole family's configuration.

The work also consolidates option persistence and metadata into the shared
`YADF.Options` unit (a single descriptor table), removing the option-list
duplication that currently exists across the CLI and the wizard.

After this change the release ships **three artifacts, identically versioned**:
`YADF.exe` + `YADFSetup.exe` + `YADFOT.bpl`.

## 2. Goals / Non-Goals

### Goals
- A standalone `.exe`: paste/load source on the left, formatted output on the
  right, all options in between, re-formatting live as settings change.
- Edits autosave immediately to the shared `yadf.ini`.
- Save current settings to any file (export profile) and load settings from any
  file (import profile); reset to defaults.
- One source of truth for option metadata, persistence, and help text in
  `YADF.Options`.
- All three artifacts carry an identical version/build number from a single
  source.
- Ship a sample `.pas` that demonstrates every formatting feature.

### Non-Goals
- No syntax highlighting / no editor IntelliSense in the memos (plain
  monospace text is sufficient).
- No multi-file / project formatting in the GUI (that's the CLI's job).
- No safety net / undo on the shared INI autosave (explicitly chosen — see §6).
- No new formatting behavior; this is tooling + consolidation only.

## 3. Background / Current State

- The engine entry point is pure and file-I/O-free:
  `function FormatSource(const ASource: string; const AOpts: TYadfOptions): string;`
  (`YADF.Layout.pas`). This is all the GUI needs to format in memory.
- `TYadfOptions` (record, `YADF.Options.pas`) holds ~33 fields: integers,
  booleans, two directory strings, an encoding enum, and logging.
- `YADF.Options.pas` already owns: `DefaultOptions`, `SharedAppDataIniPath`
  (`%APPDATA%\YADF\yadf.ini`), `WriteDefaultIniTemplate` (commented fresh file),
  `EnsureIniExists`.
- The full INI **reader** is duplicated: once in `YadfMain.pas` (CLI,
  ~lines 880-917) and again in `YADFOT.Wizard.pas` (~line 150). There is **no
  writer for current values** — only the defaults template writer.
- Per-option help text currently lives as hardcoded `;`-comment lines inside
  `WriteDefaultIniTemplate`.
- Since 1.0.1.16, shipping configs pin version info with
  `VerInfo_AutoIncVersion=false` so binaries match the release tag.

## 4. Approach (chosen: "A" — consolidate in YADF.Options)

Promote INI load into `YADF.Options`, add a value writer, and drive everything
from a single **descriptor table**. CLI, wizard, and the new GUI all call the
shared functions. (Alternatives considered: a self-contained copy inside
YADFSetup — rejected, would be a 3rd copy of the field list; building the
playground into YADFOT instead of a separate exe — rejected, doesn't match the
standalone-exe requirement and is IDE-only.)

## 5. Component Design

### 5.1 `YADF.Options` — the settings authority

A single descriptor table is the authority; persistence, the INI template, the
CLI `--help`, and the GUI all derive from it.

```pascal
type
  TOptKind = (okBool, okInt, okString, okEnum);
  TOptInfo = record
    Ident         : string;     // INI key (under [Format]) AND the field it maps to
    Group         : string;     // UI group + template section header
    Caption       : string;     // GUI label
    Hint          : string;     // one-line help: GUI tooltip, ';' comment in template, --help line
    Kind          : TOptKind;
    AffectsPreview: Boolean;     // false for Backup/BackupDir/ResultDir/Encoding/Logging
    GetVal        : function(const O: TYadfOptions): Variant;
    SetVal        : procedure(var O: TYadfOptions; const V: Variant);
  end;

const
  YADF_OPTIONS: array[0..N] of TOptInfo = ( ... );   // exactly one entry per TYadfOptions field
```

The `GetVal`/`SetVal` accessors are the only per-field code; everything else
iterates `YADF_OPTIONS`. Adding a future option = add the record field + its
`DefaultOptions` value + one table row.

New / changed public surface:

```pascal
function  DefaultOptions: TYadfOptions;                                   // (exists) reset values
function  SharedAppDataIniPath: string;                                  // (exists)
procedure WriteDefaultIniTemplate(const APath: string);                  // (changed) renders from table
function  EnsureIniExists(const APath: string): Boolean;                 // (exists)
function  LoadOptionsFromIni(const APath: string): TYadfOptions;         // NEW (table-driven; promoted)
procedure SaveOptionsToIni(const AOpts: TYadfOptions; const APath: string); // NEW (writes current values)
function  OptionsHelpText: string;                                       // NEW (table-driven CLI --help body)
```

- `SaveOptionsToIni` first ensures the commented template exists at `APath`,
  then writes each field with `TIniFile.WriteString/WriteInteger/WriteBool`.
  Because the WinAPI INI writer only rewrites the touched key lines, the `;`
  comment lines survive — saved/exported files keep their explanations.
- `LoadOptionsFromIni` reads each table entry under `[Format]`, falling back to
  `DefaultOptions` per field (keeps the existing tolerant behavior, incl. the
  `ReadBoolIni` textual-boolean handling, which moves into this unit).
- **Reset** needs no new function: caller sets `Opts := DefaultOptions` then
  `SaveOptionsToIni`.

`YadfMain.pas` and `YADFOT.Wizard.pas` drop their private readers and delegate
to `LoadOptionsFromIni`; `ReadBoolIni`/`ParseEncoding` move into `YADF.Options`
(or are re-exposed there) so both call sites compile unchanged in behavior.

### 5.2 `YADFSetup.exe` — the GUI

VCL Forms application, **Win32** (matches the YADFOT toolchain; engine units
compiled directly, no source fork — same model YADFOT already uses). Single main
form, three resizable columns separated by `TSplitter`s:

```
+-- Settings --------+-- Source ---------+-- Result ---------+
| [Load Settings]    | [Open File...]    | [Copy] [Save As]  |
| [Save As...][Reset]| file: Sample.pas  | status: OK        |
| +Layout---------+  |                   |                   |
| | MaxLen [180]   |  | (editable TMemo, | (read-only TMemo, |
| | Indent [2]     |  |  monospace;      |  monospace;       |
| +----------------+  |  paste or load   |  formatted output)|
| +Casing---------+  |  source)         |                   |
| | [x] Lowercase  |  |                   |                   |
| +----------------+  |                   |                   |
| ...grouped scroll...|                   |                   |
| INI: %APPDATA%\YADF\yadf.ini  (saved)   |                   |
+--------------------+-------------------+-------------------+
```

- **Left** — `TScrollBox` containing one `TGroupBox` per `Group`
  (Layout / Spacing / Casing / Alignment / Blank Lines / Uses & Decls /
  File & CLI). Controls are generated at runtime by iterating `YADF_OPTIONS`:
  `okBool`→`TCheckBox`, `okInt`→`TSpinEdit`, `okString`→`TEdit`,
  `okEnum`→`TComboBox`. `Hint` becomes each control's tooltip. A top button bar
  holds Load Settings / Save Settings As / Reset Defaults, and a status line
  shows the active INI path + last-saved state.
- **Middle** — editable source `TMemo` (Consolas, no word-wrap, scrollbars),
  with an Open File button and a filename label.
- **Right** — read-only result `TMemo` (Consolas), with Copy and Save Result As
  buttons and an OK/error status label.

### 5.3 Sample demo unit

Ship `Demo\Sample.pas` — a curated unit that visibly exercises every feature:
multi-var declaration splitting, all four alignment passes (const-equals,
type-colon, smart-assign, matching-shapes incl. a record-constant array),
uses-clause break, casing (lowercase keywords / upper hex / upper directives),
long-line reflow, blank-line normalization, declaration-semicolon alignment,
and the three regression shapes (`<=`/`>=` operators, `{$I}` includes between
`interface` and `uses`, and an enum with trailing `//` comments).

The sample must also include **modern Delphi (13 Florence) syntax** so the
formatter is demonstrated on current-era code, not just legacy shapes:
- **Inline variable declarations** — `var I: Integer := 0;` inside a routine
  body, plus type-inferred `var Sum := 0.0;` and an inline loop variable
  `for var K := 0 to High(A) do`.
- **Inline constants** — `const Factor = 2;` inside a `begin..end`.
- **`if` ternary expression** and the **`is not`** operator (Delphi 13 idioms
  from the project's coding standards).
- A small **generic** usage (e.g. `TList<Integer>` / `IList<T>`) and an
  **inline anonymous method** passed as an argument (covers the anon-method
  indent path fixed in 1.0.0.15).

`Sample.pas` itself must be valid, compilable Delphi 13 and remain
formatter-stable (idempotent) at shipped defaults. YADFSetup auto-loads it into
the Source pane on first launch (looked up next to the exe, then
`Demo\Sample.pas`) so the demo is immediate; users may Open their own files at
any time.

## 6. Behavior / Data Flow

- **Option changed** → marshal controls → `Opts` → `SaveOptionsToIni(shared)`
  (immediate autosave, no safety net — explicitly chosen) → if the changed
  option's `AffectsPreview` is true, re-format.
- **Source typed** → 300 ms debounce → re-format. **Source file loaded** →
  re-format immediately.
- **Re-format** = `Result.Text := FormatSource(Source.Text, Opts)` wrapped in
  `try/except`; on exception the Result pane shows `[Format error] <message>`
  and the previous output is replaced by that line (never crashes).
- **Buttons:**
  - *Open File* — load any file into Source (default/ANSI text load), reformat.
  - *Save Settings As* — `SaveOptionsToIni(Opts, chosenPath)` via SaveDialog;
    exports a profile, does **not** touch the shared INI.
  - *Load Settings* — `LoadOptionsFromIni(chosenPath)` via OpenDialog →
    controls ← Opts → autosave to shared INI → reformat (current state always
    mirrors the shared INI, consistent with the autosave model).
  - *Reset Defaults* — confirm prompt (it overwrites the shared INI) →
    `Opts := DefaultOptions` → controls ← Opts → autosave → reformat.
  - *Copy* / *Save Result As* — clipboard / write the right-pane text.
- File/CLI-only options (`AffectsPreview = false`: Backup, BackupDir, ResultDir,
  Encoding, Logging) autosave but skip the reformat.

## 7. Versioning (single source across all 3 artifacts)

- A single `YADF.Version.inc` defines the version string/parts (e.g.
  `1.0.4.0` — the release that introduces YADFSetup). It is `{$I}`-included by
  any unit that needs the version in code (YADFSetup About box / window caption,
  `YADF.exe --version`, the wizard's about text).
- `build\build_all.bat` reads that single version and passes
  `/p:VerInfo_MajorVer=1 /p:VerInfo_MinorVer=0 /p:VerInfo_Release=4
  /p:VerInfo_Build=0` (values from the one source) to **all three** project
  builds, with `VerInfo_AutoIncVersion=false`. Result: `YADF.exe`,
  `YADFSetup.exe`, and `YADFOT.bpl` always carry an identical
  FileVersion/ProductVersion, set in one place.

## 8. Testing

- **Headless unit tests** (extend `Test/`):
  - Round-trip identity: `DefaultOptions → SaveOptionsToIni → LoadOptionsFromIni`
    equals the original for every field.
  - Comment preservation: saving over the template leaves all `;` comment lines
    intact.
  - **Descriptor-table completeness:** assert every `TYadfOptions` field is
    represented exactly once in `YADF_OPTIONS` (the guard that keeps "single
    source" honest as the record grows).
  - Help text: `OptionsHelpText` / template render covers every table entry.
- **Regression:** the existing format corpus must still pass after `YadfMain` /
  `YADFOT.Wizard` delegate to the shared `LoadOptionsFromIni` (proves the
  extract-and-delegate changed no behavior).
- **Build smoke:** all three projects build; a minimal launch smoke for
  `YADFSetup.exe` (starts, loads `Demo\Sample.pas`, produces non-empty Result).

## 9. Build & Packaging

- New `YADFSetup.dpr` / `YADFSetup.dproj` (VCL, Win32), compiling the engine
  units directly.
- `build\build_all.bat` extended to build `YADFSetup.exe` and apply the unified
  version stamp to all three targets.
- Release zip now contains: `YADF.exe`, `YADFSetup.exe`, `YADFOT.bpl`,
  `Demo\Sample.pas`, `README.md`, `CHANGELOG.md`, `LICENSE`. No `yadf.ini`
  (auto-created on first run, as today).
- `README.md` gains a YADFSetup section; `CHANGELOG.md` gets the release entry.

## 10. Risks / Mitigations

- **Extracting the reader could subtly change parsing** → covered by the
  round-trip + corpus regression tests; the extract is mechanical.
- **Autosave overwrites the shared INI during experimentation** (by design) →
  documented in-app (status line shows the live INI path) and in README;
  Save/Load profile + Reset give the user explicit control.
- **`TIniFile` comment preservation depends on the WinAPI writer behavior** →
  verified by the comment-preservation test; if it ever regresses, fall back to
  rewriting the full commented template with substituted values.
- **Large source live-reformat lag** → 300 ms debounce on typing; option changes
  reformat once. (No hard size cap chosen; can add later if needed.)

## 11. Open Questions

- Exact release number (1.0.4.0 assumed) — confirm at build time.
- Whether *Save Result As* is worth shipping in v1 (low cost; included unless
  trimmed during planning).
