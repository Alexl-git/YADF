# Changelog

All notable changes to YADF (and the YADFOT IDE wizard, which shares
the same engine) are recorded here. Versions track the build counter
stamped into `YADF.exe` (`1.0.1.<build>`; the fourth field is the
auto-incrementing build number). Entries below `1.0.1.16` predate the
scheme correction and keep their original `1.0.0.x` headings.

The format is loosely based on [Keep a Changelog](https://keepachangelog.com/).

## [1.0.1.16] -- 2026-05-15

### Changed
- **Aligned columns are compacted left.** The `:`/`=`/`:=` alignment
  passes used to anchor on the rightmost *current* anchor position,
  which froze any whitespace that already sat before the anchor into
  the shared column. They now target the tightest column that still
  keeps the run aligned -- `max(content-extent) + min(gap) + 1` -- so
  when every line carries surplus padding before an anchor the whole
  column shifts left instead of being pushed out. `SmartAlignAssignments`
  also deletes (not just inserts) padding when an earlier anchor's
  cascade over-pads a later one. Byte-for-byte unchanged on already
  tight runs.
- **Aligned anchor spacing is normalized to the rule.** Before the
  smart-align pass measures a run it strips rule-violating whitespace:
  member-access `.` is glued on both sides and `;` has no space before
  it. Alignment then re-adds a space before an anchor only on the
  shorter lines that need it to reach the shared column -- the
  extent-defining line of every column carries exactly the rule gap
  (`0` for `.`, `0` before `;`, `:=` per `AssignNoSpaceBefore` /
  `AssignSpaceAfter`). Scoped to multi-line shape-matched `:=` runs;
  lone lines and non-aligned dotted code are left as the pass-1
  emitter produced them. Idempotent; no change to the DelphiAST
  snippet corpus.

### Added
- **YADFOT refuses form / data-module units.** Formatting a unit that
  has an open Form Designer rewrote the whole editor buffer out from
  under the designer, invalidating its source-position map; the IDE
  then access-violated inside `VCLFormDesigner.TVCLRootDesigner.DoSave`
  on the next *File > Save All*. YADFOT now detects an associated
  `IOTAFormEditor` on the active module and declines with a message
  pointing to the YADF command-line tool (whose `SaveFile` already
  performs the IDE-reload handshake). Plain `.pas`/`.dpr`/`.dpk`/`.inc`
  are unaffected. (The reformatted source was always valid -- the crash
  was the IDE designer's stale cache, not corrupted output.)

### Build
- Version info pinned to `1.0.1.16` for the shipping configs
  (`VerInfo_AutoIncVersion=false`; YADF Debug Win32 + Win64, YADFOT
  Debug Win32) so binaries match the release tag. YADFOT is a
  design-only package and RAD Studio is 32-bit, so the Win64 YADFOT
  target is not a usable artifact and is not shipped.

## [1.0.0.15] -- 2026-05-15

### Fixed
- **Spurious indentation after inline anonymous methods.** An inline
  `procedure(...) begin ... end` / `function(...): T begin ... end`
  passed as a call argument left `ReindentByDepth` with a phantom open
  procedure region, adding a +1 indent to every line after the call --
  cascading through the rest of the routine and pushing its closing
  `end;` one level too deep. The `ptProcedure`/`ptFunction` handler now
  requires `ParensDepth = 0`, so anonymous-method expressions nested in
  argument parens no longer open a procedure region.
  (Found while formatting `Blueprint4.pas`.)

## [1.0.0.14] -- 2026-05-14

### Fixed
- **`<=` / `>=` mangled by the column-alignment pass.** The const-equals
  alignment pass treated the trailing `=` of `<=` and `>=` as a
  candidate anchor and right-padded it, producing dcc-invalid output
  like `>          = N`. `FindAnchorAtTopLevel` now skips a `=`
  preceded by `<` or `>` in addition to the existing `:=` case. (All
  two-char operators in the lexer were audited; this was the only
  affected scan.)

### Added
- **YADFOT -- YADF Open Tools.** A design-time, Win32 Delphi IDE
  package that formats the current source-editor buffer with the YADF
  engine. Entry points: `Help -> Tools -> YADFOT: Format Current
  Buffer` and the `Ctrl+Shift+Alt+F` shortcut. Buffer I/O is UTF-8 via
  the IDE edit reader/writer; writes are undoable. Config resolved from
  `yadf.ini` (source dir, then project dir, then
  `%APPDATA%\YADFOT\yadf.ini`) or compiled-in defaults. No YADF source
  was forked -- the package compiles the engine units directly.
- Regression test corpus entries: `Test/Cases/compound_operators.pas`,
  `Test/Cases/anon_proc_indent.pas`.

### Documentation
- Consolidated `README.md` covering both `YADF.exe` and `YADFOT.bpl`.
- Extensive explanatory comments added across `YADF.Layout.pas`
  (unit-level pipeline overview plus per-function headers).

## [1.0.0.x] -- earlier

Engine fixes prior to the changelog being introduced (from git
history):

- Fix `StartsBlockBoundary` matching identifiers as keywords
  (`EndIdx` vs `end`).
- Indent `repeat`..`until` block bodies in `ReindentByDepth`.
- Preserve multi-line block comments through reflow and
  `BreakLongLines`.
- Credit Roman Yankovsky / DelphiAST in README and build instructions.
