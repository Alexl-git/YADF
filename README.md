# YADF -- Yet Another Delphi Formatter

A Pascal/Delphi source code formatter, written in Delphi 13. Reformats `.pas`
files according to a configurable rule set: line-length budgeting, structural
re-indentation, capitalization, and column alignment.

YADF ships in three flavours, built from the same engine:

- **`YADF.exe`** — a stand-alone CLI for formatting files, folders, and
  whole `.dpr`/`.dproj` projects (see [CLI quick start](#cli-quick-start)).
- **`YADFSetup.exe`** — a visual settings editor / format playground
  (see [YADFSetup](#yadfsetup)).
- **`YADFOT.bpl`** — a Delphi IDE design-time package ("YADF Open Tools")
  that adds a `Help → Tools → YADFOT: Format Current Buffer` menu item
  and a `Ctrl+Shift+Alt+F` shortcut to format the current source-editor
  buffer (see [YADFOT install](#yadfot-install)).

All three artifacts are produced by this single project tree and share one
`yadf.ini` configuration. `build_all.bat` builds them together with a single
version stamp.

## YADFSetup

`YADFSetup.exe` is a three-column GUI — **Settings | Source | Result**. Load any
`.pas` on the left, watch it reformat live on the right, and tune every option
in between. It auto-loads `Demo\Sample.pas` on first launch so you can see every
feature at work immediately.

- Changes **autosave** to the shared `yadf.ini` (`%APPDATA%\YADF\yadf.ini`) that
  `YADF.exe` and `YADFOT.bpl` also read — so YADFSetup is the visual front-end
  for the whole family's configuration.
- **Load Settings / Save As…** — import or export an option profile (any `.ini`).
- **Reset** — restore the shipped defaults (overwrites the shared `yadf.ini`).

Because edits autosave to the shared config, experimenting in YADFSetup changes
how the CLI and IDE wizard format from then on. Use **Save As…** to keep a
profile and **Reset** to return to defaults. The active INI path is shown at the
bottom of the Settings column.

## YADFOT install

YADFOT is a design-time, Win32-only Delphi IDE package. The IDE itself
is 32-bit, so the BPL must be Win32 even on a 64-bit machine.

### From the IDE

1. Open `YADFOT.dproj` in Delphi 13.
2. Active platform: **Win32**, configuration **Release** (Debug works too).
3. Project → Build YADFOT. The output is `Win32\Release\EXE\YADFOT.bpl`,
   right next to where `YADF.exe` lands.
4. Component → Install Packages → Add… → browse to that `YADFOT.bpl` → OK.

The wizard registers itself on package load -- no IDE restart needed.

### From the command line

```cmd
cmd.exe /c "call \"C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat\" ^
        && msbuild /t:Build /p:Config=Release /p:Platform=Win32 YADFOT.dproj"
```

Then install via the IDE (step 4 above).

### Using the wizard

Two entry points appear in the IDE after install:

1. **Menu** → `Help` → `Tools` → `YADFOT: Format Current Buffer`
   (this is the standard location for IOTAMenuWizard items in the
   Delphi IDE — installed wizards live under *Help → Tools*, not
   directly under *Tools*).
2. **Keyboard shortcut** → `Ctrl + Shift + Alt + F`

The shortcut is registered as a Delphi keyboard binding named
`YADFOT`. If the chord clashes with something on your machine you
can rebind it under `Tools → Options → User Interface → Editor →
Key Mappings` (look for the `YADFOT` entry), or change it in source
at the call to `BindingServices.AddKeyBinding` in
[YADFOT.Wizard.pas](YADFOT.Wizard.pas) and rebuild.

YADFOT verifies the active edit view is a code buffer before doing anything.
Supported extensions: `.pas` `.dpr` `.dpk` `.inc`. If the active view is a
form designer, project options page, welcome page, or any other non-code
editor, the wizard reports it and exits without changes -- it deliberately
does **not** auto-jump to a sibling `.pas` behind a form. Click into the
code editor first, then invoke the wizard.

The buffer does not need to be saved -- the in-memory contents are read,
formatted, and rewritten through an undoable IDE edit (so Ctrl+Z reverts
the format).

**Encoding.** All buffer I/O is UTF-8 by way of the IDE's edit
reader/writer; the on-disk encoding of the file is irrelevant. The CLI's
`Encoding` INI key (`ANSI` / `UTF-8` / `UTF-16`) only affects file I/O
and is intentionally ignored by YADFOT.

**INI lookup (unified across YADF.exe and YADFOT.bpl since 1.0.2).**

Both the CLI and the IDE wizard look for `yadf.ini` in the same order
(first hit wins) so whichever tool runs first creates the file the other
will find:

1. The source file's directory, walking up to 8 parents (project-local
   override; YADFOT only)
2. The active project's directory, walking up to 8 parents (YADFOT only)
3. The CLI's current working directory, walking up to 9 parents (YADF.exe
   only — typically the project root)
4. The directory of `YADF.exe` itself, walking up to 5 parents (portable-
   app pattern: drop a `yadf.ini` next to the EXE)
5. Legacy `%APPDATA%\YADFOT\yadf.ini` (read-only fallback for users
   upgrading from 1.0.1.x; never written to)
6. **`%APPDATA%\YADF\yadf.ini`** — shared per-user fallback. If nothing
   exists anywhere above, a fully-commented template is written here on
   first run and used. Typically
   `C:\Users\<user>\AppData\Roaming\YADF\yadf.ini`.

**First-run experience.** No INI ships in the release zip. The first time
you run `YADF.exe` (or save a file with `YADFOT` registered), an INI is
created at `%APPDATA%\YADF\yadf.ini` with every option, its default, and
a one-line explanation. Edit values and re-run; or drop a project-local
`yadf.ini` to override per-project.

The CLI prints `Created default config: <path>` on the first run that
materialises the template, so you know where to find it.

The `[Format]` section keys match the CLI keys exactly. The only key the
IDE wizard ignores is `Encoding`, since IDE buffer I/O is always UTF-8.

### Uninstall

Component → Install Packages → select `YADFOT` → Remove.

## CLI quick start

```cmd
yadf MyUnit.pas
```

Format a single `.pas` file in place — the source is overwritten with the
formatted output, no backup. This is the default; if you want a copy of the
original kept, opt in:

```cmd
yadf MyUnit.pas --b
```

In-place format with a sibling backup `MyUnit.pas.BCK1` (then `BCK2`, `BCK3`,
...) next to the source. To send backups to a central folder with timestamped
`.bak` names instead, give `--b` a folder argument:

```cmd
yadf MyUnit.pas --b D:\YADF-backups
```

To send the formatted output somewhere else and leave the source untouched:

```cmd
yadf MyUnit.pas --o D:\out\MyUnit.formatted.pas    :: write to this exact file
yadf C:\src\*.pas --of D:\formatted               :: every result into this folder
```

```cmd
yadf MyProject.dpr
```

Format the `.dpr` and every local `.pas` named in its `uses` clause. `*.pas`
wildcards (`yadf C:\src\*.pas`) and `.dproj` project files work the same way
— `.dproj` is parsed for its `<DCCReference Include="...pas"/>` entries.

```cmd
yadf -h
```

Shows the full option list, every CLI flag, and the current effective
values pulled from `yadf.ini`.

## Features

**Layout**
- Configurable max line length (default 180), indent step (default 2), tab
  width (default 4)
- Full reflow: drops user line breaks where structurally non-essential, joins
  lines that fit, breaks lines that overflow
- Block-aware breaking: `uses` clauses, parenthesized argument lists, bracket
  literals all break to one item per line when needed
- Operator-chain breaking: long arithmetic/logical expressions break with the
  operator leading each new line
- Hanging indent for parens-broken statements: items at `LineWS + 2*Indent`,
  closing paren at `LineWS`

**Indentation**
- Re-indents every line based on structural depth, ignoring source whitespace
- Tracks `type/var/const` sections, `class`/`record`/`object`/`interface`
  declarations, `begin`/`end` blocks, `case`/`try`/`asm`
- Visibility keyword bonus: members inside `private`/`public`/`protected`/
  `published` indent one level deeper
- `if`/`while`/`for` body bonus: single-statement bodies after `then`/`do`/
  `else` indent one level deeper, persisting across multi-line bodies
- Case-alternative bonus: bodies after `LABEL:` indent one level deeper
- `else` aligns with its `if`; `else if` chains stay on one line

**Capitalization**
- Lowercase reserved keywords (`begin`, `end`, `if`, `else`, `var`, ...)
- Uppercase hex digits in `$NN` numeric literals and exponent letter `E`
- Uppercase compiler-directive names (`{$IFDEF}`, `{$DEFINE}`, ...)
- First-occurrence identifier-case normalization (consistent casing throughout
  the file)

**Pass-2 alignment**
- Plain align of `:` in declarations and `=` in `const` blocks across
  consecutive lines
- Smart align of `:=` assignments: when adjacent lines share the same token
  shape (same sequence of operators/punctuation, identifier names may differ),
  every common anchor (`.`, `:=`, `(`, `,`, `)`, `;`) is padded so the
  anchors line up
- Aligned columns are kept **tight**: an anchor's spacing rule wins
  (member-access `.` is glued on both sides, no space before `;`, `:=`
  spacing per `AssignNoSpaceBefore`/`AssignSpaceAfter`), and a column is
  never pushed right by padding that every line in the run shares — a
  space appears before an anchor only on the shorter lines that need it
  to reach the shared column

**Other**
- Always emits CRLF line endings
- Reads and writes file bytes in the encoding chosen by `Encoding=` in
  `yadf.ini` (default `ANSI`; `UTF-8-BOM` and `UTF-16-BOM` also supported).
  Existing BOM in input is auto-detected on load. (YADFOT bypasses this
  setting and always exchanges UTF-8 with the IDE buffer.)
- Backups are opt-in: in-place formatting overwrites the source unless
  you set `Backup=true` in `yadf.ini` or pass `--b` on the command line.
  When backups are on, they go to a sibling `<source>.BCK<N>` (default)
  or to a folder you specify with `--b <folder>` (timestamped `.bak`).
- Trailing whitespace stripped on every line
- Consecutive blank lines collapsed to a configurable cap (default 1)
- Optional blank-line insertion before sections, methods, type sections
- Block-end labels: long `begin..end` blocks get `// while`, `// procedure`,
  etc. trailing comments
- Optional unclosed-block markers: when source has unmatched `begin`/`record`,
  emit `// TODO -oYADF : 'begin' on line N has no matching 'end'` so they show
  up in the IDE's To Do List

**Robustness**
- The format pipeline is idempotent: `format(format(x)) == format(x)`
- `--check <file>` verifies byte-faithful round-trip (token stream emits
  identical bytes back)
- Tolerates structurally-broken Pascal source (missing `end`s) without
  crashing

## Configuration

YADF (CLI) and YADFOT (IDE wizard) share a unified lookup hierarchy
documented in detail under [YADFOT install → INI lookup](#yadfot-install)
above. Summary: project-local `yadf.ini` (walked up from the source file,
the active project, or the CLI's cwd), then the EXE's own folder, then
the shared fallback `%APPDATA%\YADF\yadf.ini`. No INI ships in the
release zip — first run creates a fully-commented template at the
fallback location. CLI flags override INI values; INI values override
compiled-in defaults. See the auto-created `yadf.ini` for the
documented option list.

YADFOT (IDE wizard) reads the same `[Format]` keys with a different search
order — see [YADFOT install](#yadfot-install) above.

## Building

Requires Delphi 13 (RAD Studio 37.0). Depends on
[DelphiAST](https://github.com/RomanYankovsky/DelphiAST) for its lexer; the
project files expect DelphiAST checked out at `..\DelphiAST` relative to YADF.

Build the CLI:

```cmd
cmd /c "call \"C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat\" ^
        && msbuild /t:Build /p:Config=Release /p:Platform=Win64 YADF.dproj"
```

Build the IDE wizard package:

```cmd
cmd /c "call \"C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat\" ^
        && msbuild /t:Build /p:Config=Release /p:Platform=Win32 YADFOT.dproj"
```

Build the settings editor:

```cmd
cmd /c "call \"C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat\" ^
        && msbuild /t:Build /p:Config=Release /p:Platform=Win32 YADFSetup.dproj"
```

Or build **all three at once with one shared version stamp**:

```cmd
build_all.bat
```

`build_all.bat` is the single source of truth for the release version: it sets
`YADF_MAJOR/MINOR/RELEASE/BUILD` once and stamps the identical FileVersion into
`YADF.exe`, `YADFSetup.exe`, and `YADFOT.bpl` (keep `YADF.Version.inc` in sync
for the in-app version string). All outputs land in `Win32\Release\EXE\`
(plus `Win64\Release\EXE\` for the CLI); `YADFOT.bpl` is Win32-only, since the
Delphi IDE is 32-bit, while `YADF.exe` builds for Win32 and Win64.

## Project layout

```
YADF\
  YADF.Tokens.pas       lexer wrapper + token stream
  YADF.Options.pas      TYadfOptions + YADF_OPTIONS table + INI load/save
  YADF.Groups.pas       structural group parser (begin/end nesting, etc.)
  YADF.Layout.pas       FormatSource -- the engine entry point
  YADF.Debug.pas        debug-tree dump (CLI --debug-tree)
  YADF.Version.inc      single-source version string (display)
  YadfMain.pas          CLI argument parser + driver
  YADF.dpr / .dproj     CLI project
  uYADFSetupMain.pas    YADFSetup form (3-column playground)
  YADFSetup.dpr/.dproj  settings-editor GUI project
  YADFOT.Wizard.pas     IDE wizard (ToolsAPI + buffer I/O + INI loader)
  YADFOT.dpk / .dproj   IDE design-time package
  Demo\Sample.pas       feature-demonstration unit (auto-loaded by YADFSetup)
  build_all.bat         builds all 3 artifacts with one version stamp
  yadf.ini              shared CLI + wizard + GUI config (optional)
```

## Acknowledgements

YADF is built on top of [DelphiAST](https://github.com/RomanYankovsky/DelphiAST)
by [Roman Yankovsky](https://github.com/RomanYankovsky) and contributors. The
lexer (`SimpleParser.Lexer`) handles all token-level details including modern
Delphi syntax (multi-line strings, inline vars, generic constraints, etc.) and
made this project possible.

To build YADF from source you'll need DelphiAST checked out alongside this
repo — clone it from
[RomanYankovsky/DelphiAST](https://github.com/RomanYankovsky/DelphiAST).

DelphiAST is Copyright (c) 2014-2020 Roman Yankovsky (roman@yankovsky.me) et
al, released under the Mozilla Public License v2.0.

## License

YADF is released under the Mozilla Public License v2.0. See `LICENSE` for the
full text. This is the same license as DelphiAST.

```
Copyright (c) 2026 Alexander Liberov

This Source Code Form is subject to the terms of the Mozilla Public License,
v. 2.0. If a copy of the MPL was not distributed with this file, You can
obtain one at https://mozilla.org/MPL/2.0/.
```
