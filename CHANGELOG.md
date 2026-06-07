# Changelog

All notable changes to YADF (and the YADFOT IDE wizard, which shares
the same engine) are recorded here. Versions track the build counter
stamped into `YADF.exe` (`1.0.1.<build>`; the fourth field is the
auto-incrementing build number). Entries below `1.0.1.16` predate the
scheme correction and keep their original `1.0.0.x` headings.

The format is loosely based on [Keep a Changelog](https://keepachangelog.com/).

## [1.0.6.2] -- 2026-06-07

### Fixed

- **Class `var` / `class var` sections under a visibility specifier now indent
  consistently** (surfaced via DelphiAST issue #333). Inside a class with a
  `private`/`protected`/... specifier the re-indent pass cleared the visibility level
  on every `var`/`const`/`type` section, so fields landed at the *same* depth as their
  `var` keyword and a following section dropped a level. Now every `var`/`class var`
  section under a visibility specifier aligns, and its fields sit one level deeper.
  `class var` / `class const` / `class type` headers dedent like a bare section
  keyword. A section that shares the visibility specifier's line (e.g. `public type`)
  is left unchanged (no double-indent).

## [1.0.6.1] -- 2026-06-05

### Fixed

- **`of object` method-pointer / event types no longer break formatting.** A type
  like `TNotifyEvent = procedure(Sender: TObject) of object;` was mishandled two
  ways: the group parser treated the `object` modifier as an `object...end` block
  opener (stamping a spurious `// object` label on the unit's `end.` and cascading
  indentation), and the re-indent pass treated `= procedure` / `= function` as a
  routine declaration, closing the surrounding `type` section so every following
  declaration dropped a level. Both are now guarded -- the fixes fire only on
  `of object` and on `procedure`/`function` immediately after `=`, so real object
  blocks and routine declarations are unaffected. Procedural and method-pointer
  type declarations now keep correct indentation.

## [1.0.6.0] -- 2026-06-04

### Added

- **`Delphi10Compat` (default `false`; `--d10` CLI flag).** An opt-in transform
  that rewrites **inline `var` declarations** into a classic top-of-routine `var`
  block so code written on Delphi 11/12/13 can build on **Delphi 10.2.3 (Tokyo)**.
  Explicit-typed vars and typed `for`-loop vars hoist mechanically (a `var` block is
  created if absent); multi-name decls hoist each name. Inferred initializers with a
  literal RHS get a best-effort type (`Integer`/`Extended`/`string`/`Boolean`,
  `T.Create` -> `T`) with a `// YADF Delphi10: inferred type, verify` comment.
  Un-inferable vars, different-type name collisions, and inline vars inside
  anonymous methods are left in place with a `// TODO -oYADF : ...` marker quoting
  the original line. Idempotent.
  - **Not full Delphi 10 compliance:** only inline variables are downgraded. The
    `if` ternary expression, inline constants, and managed records have no
    mechanical Delphi 10 equivalent and are left untouched.
  - We have no pre-10.3 Delphi to test against, so the transform is best-effort and
    unverified on a real Tokyo toolchain; the prebuilt `YADF.exe` needs no Delphi
    installed. See the README "Delphi 10 compatibility" section.

### Fixed

- **Multi-line (`'''...'''`) string literals are no longer corrupted by formatting.**
  YADF's Stage 3/4 string passes (re-indent, reflow, alignment) used to treat the
  *interior* of a triple-quoted literal as code -- collapsing the opening newline to
  a space and re-indenting the body, silently changing the string's value -- and
  `ReindentByDepth`'s depth tracker even scanned literal interiors for `begin`/`end`.
  The engine now shields every multi-line string token before those passes and
  restores it verbatim afterward, so literal contents pass through byte-for-byte.
- Adopted the upstream DelphiAST fix (PR #337 by Uwe Raabe, issue #336) for the
  lexer's multi-line `StringProc` in the bundled lexer dependency.

## [1.0.5.0] -- 2026-06-02

### Added

- **`SpaceAroundOperators` (default `true`).** A token-level pass that puts one
  space around binary operators: `+ - * / = <= >= <>`. It is unary-safe (`-5`,
  `:= -X`, `(-A)` stay attached) and generics-safe (bare `<` / `>` are never
  touched, so `TList<Integer>` is preserved); `..` ranges, `^` pointers, and
  `@` address-of are left intact. Toggle it in YADFSetup or via the
  `SpaceAroundOperators` INI key.

### Fixed

- **Anonymous method passed as an argument no longer under-indents.** A
  multi-line `List.Sort(function ... begin ... end)` had its `function` header
  collapsed to the procedure-region column. `ReindentByDepth` now applies the
  proc-region indent only to real declarations (`ParensDepth = 0`); an
  anonymous method inside an expression keeps the normal expression depth and
  lines up under the call argument.

## [1.0.4.0] -- 2026-06-02

### Added

- **YADFSetup.exe** -- a visual settings editor / format playground with three
  columns (Settings | Source | Result). Load any `.pas`, watch it reformat live
  as you tune every option, and autosave the shared `yadf.ini` that the CLI and
  IDE wizard also use. Save/Load option profiles to any file; Reset to defaults.
  Ships with `Demo\Sample.pas`, auto-loaded on first launch, which demonstrates
  every feature plus modern Delphi 13 syntax (inline `var`/`const`, type
  inference, inline-loop vars, `if` ternary, `is not`, generics, inline
  anonymous methods).
- **Single option-descriptor table in `YADF.Options`** (`YADF_OPTIONS`): one
  entry per `TYadfOptions` field, now the sole source for INI load/save, the
  `yadf.ini` template, and option help. New public API: `OptionTable`,
  `LoadOptionsFromIni`, `SaveOptionsToIni`, `OptionsHelpText` (plus
  `ParseEncoding`/`EncodingToStr`/`ReadBoolIni`, moved here from `YadfMain`).
  `SaveOptionsToIni` writes current values over the commented template so the
  explanatory comments survive a round-trip.
- **`build_all.bat`** builds all three artifacts (`YADF.exe`, `YADFSetup.exe`,
  `YADFOT.bpl`) with one shared version stamp, so their FileVersion is always
  identical. `YADF.Version.inc` carries the matching in-app version string.
- Headless `Test\OptionsTest.dpr` (round-trip identity, comment preservation,
  descriptor completeness, help coverage) and `Test\smoke_yadfsetup.ps1`.

### Fixed

- **YADFOT wizard ignored three alignment options.** `YADFOT.Wizard.pas` had a
  hand-maintained INI reader that had drifted from the CLI, silently ignoring
  `AlignMatchingShapes`, `AlignShapeMinAnchors`, and `AlignCommentMaxShift`.
  Both the CLI and the wizard now delegate to the shared `LoadOptionsFromIni`,
  so all three tools honor exactly the same options.

### Distribution

The release zip now contains `YADF.exe`, `YADFSetup.exe`, `YADFOT.bpl`,
`Demo\Sample.pas`, `README.md`, `CHANGELOG.md`, `LICENSE`. No `yadf.ini`
(auto-created on first run).

## [1.0.3.0] -- 2026-05-27

### Added

- **`SplitMultiVarDecls` (default `true`).** Combined declarations
  like `I, J: integer;` are now split into one line per name
  (`I: integer;` / `J: integer;`) so the type colons align cleanly.
  Applies to top-level `var`/`const` blocks and record/class field
  declarations. Procedure parameter lists inside `(...)` are
  untouched (splitting them would change call signatures).
- **`AlignDeclSemicolons` (default `true`).** After
  `AlignTypeColon`, the trailing `;` on consecutive declaration
  lines is padded so the right edge is flush. Only fires on lines
  that match `name : type;` -- regular statement semicolons are
  not touched.

### Example

Before:
```pascal
var
  I, J: Integer;
  Sum, Product, Quotient: Double;
  Done: Boolean;
```

After:
```pascal
var
  I       : Integer;
  J       : Integer;
  Sum     : Double ;
  Product : Double ;
  Quotient: Double ;
  Done    : Boolean;
```

Parameter list (NOT split):
```pascal
procedure DoIt(A, B: Integer; const Msg: string);  // untouched
```

### Implementation

`SplitMultiVarDeclarations` (in `YADF.Layout.pas`) tracks paren
depth, brace comments, paren-star comments, and string literals
across lines so the multi-var pattern only matches at top-level
declaration depth. `AlignDeclarationSemicolons` runs after
`AlignByAnchor(':')` so it sees the colons in their final
column; it identifies declaration-shaped lines (top-level `:`
followed by `;` with at most a trailing `// comment`) and groups
consecutive ones into alignment runs.

---

## [1.0.2.0] -- 2026-05-27

### Added

- **First-run INI auto-creation.** When no `yadf.ini` exists anywhere
  in the lookup hierarchy, both `YADF.exe` and `YADFOT.bpl` now write
  a fully-commented template to the shared fallback location and use
  it. The template documents every option with its default and a
  one-line explanation so a fresh install needs zero shell-flag
  ceremony to start formatting. `YADF.exe` prints
  `Created default config: <path>` on the run that materialises the
  template.
- **Unified INI lookup hierarchy across CLI and IDE wizard.** YADF.exe
  and YADFOT.bpl now share the same fallback: `%APPDATA%\YADF\yadf.ini`
  (was `%APPDATA%\YADFOT\yadf.ini` for the wizard alone, and "next to
  the exe" for the CLI alone). Whichever tool runs first creates the
  file the other will find. Project-local overrides still take
  precedence via walk-up search.
- **`SharedAppDataIniPath` / `EnsureIniExists` / `WriteDefaultIniTemplate`**
  added to `YADF.Options.pas` so both `YadfMain.pas` (CLI) and
  `YADFOT.Wizard.pas` (IDE wizard) call the same code path.

### Changed

- `%APPDATA%\YADFOT\yadf.ini` (the 1.0.1.x wizard-only location) is
  now a **read-only legacy fallback** — YADFOT still reads it if
  present so existing users don't lose their config, but writes go to
  `%APPDATA%\YADF\yadf.ini`. To migrate, copy the file once.
- `YADF.exe`'s `DefaultIniPath` now walks up from cwd (project root)
  first, then the EXE folder, then the shared AppData fallback. The
  previous behavior walked only from the EXE folder.

### Distribution

The release zip contains:
- `YADF.exe` (Win64 console)
- `YADFOT.bpl` (Win32 IDE wizard for RAD Studio 12 / Delphi 13)
- `README.md`, `CHANGELOG.md`, `LICENSE`
- **No `yadf.ini`** — auto-created on first run.

---

## [1.0.1.18] -- 2026-05-18

### Fixed

- **Declaration-colon field/var blocks no longer staggered by
  Smart Align.** `SmartAlignAssignments` runs after `AlignByAnchor(':')`
  and was re-compacting shape-matched sub-runs to their own tighter
  column. In a `name : type ;` block the type-name token class
  fragments the skeleton -- the keyword `string` keeps a structural
  anchor (`: string ;`, 3 anchors) while identifier types
  (`integer`, `Boolean`, `TStringList`) do not (`: type ;`, 2
  anchors) -- so consecutive `: string;` lines were pulled to a
  different colon column than their `: integer;` neighbours, shearing
  one uniform field list into staggered columns. A declaration-colon
  line (shape's first anchor is `:` with no `:=`) is now treated as
  shape-ineligible and left to `AlignByAnchor(':')`, which already
  aligns the whole block uniformly. Record-constant arrays (shape
  starts with `(`) and properties (starts with `property`) are
  unaffected and still align. No corpus footprint change (still 2
  files); 0 crashes; idempotent.

## [1.0.1.17] -- 2026-05-17

### Improve Smart Align

- **Smart-align generalized beyond `:=` (new `AlignMatchingShapes`,
  default on).** The shape engine (`ComputeLineShape` / `ShapesMatch`)
  already reduced each line to its operator skeleton; only a `:=`-only
  gate kept it from acting on anything else. Now any run of 2+ adjacent
  lines with an identical structural skeleton -- record-constant
  arrays, declaration lists, repeated calls -- has every shared anchor
  padded to a common column. Lines whose skeletons differ are never
  touched. Off-switch: `AlignMatchingShapes=false`.
- **`AlignShapeMinAnchors` (default 3).** Floor on how many structural
  anchors a non-`:=` run's shared skeleton must have before it aligns,
  so trivial 1-2 symbol shapes (every `Foo(x);`) don't trigger noisy
  padding across ordinary code. `:=` lines are exempt from the floor.
- **Trailing `//` alignment (`AlignCommentMaxShift`, default 7).** In a
  shape-matched run where every line carries a top-level `//`, the
  comments are pulled to one column -- but only when no line must move
  more than N spaces to get there (far-flung comments are left where
  the author put them). `0` disables; the shared column is still
  bounded by `AlignMaxColumn`.
- **A line-terminal `;` is never aligned.** Padding to a shared column
  before a statement-terminating `;` would reintroduce exactly the
  space-before-`;` the tighten pass removes and wreck property/var
  lists whose tails vary. Interior `;` (record-literal field
  separators) still align, so grid-shaped const arrays keep their
  columns.

### Changed

- **`AlignMaxColumn` default raised 100 -> 140.** So typical
  record-constant tables align out of the box under
  `AlignMatchingShapes` without a per-project override. Very wide
  tables may still need it raised further; runs whose widest anchor
  would cross the column are still left untouched.

### Fixed

- **`yadf.ini` textual booleans were silently ignored (pre-existing).**
  Delphi's `TIniFile.ReadBool` only honours numeric `0`/`1`, so every
  documented textual `true`/`false` in `yadf.ini` fell through to the
  compiled default -- a user who set `Option=false` saw no effect. A
  new `ReadBoolIni` helper accepts `1/0`, `true/false`, `yes/no`,
  `on/off` (case/space-insensitive); all `Format` boolean reads now use
  it. Integer options were always read correctly.

### Tests

- New regression `Test/Cases/record_array_const_align.pas` (a 32-row
  record-constant array). Corpus footprint at shipped defaults: 2 of 46
  files change, both improvements; 0 crashes; output idempotent.

## [1.0.1.16] -- 2026-05-15

### Fixed
- **Code no longer commented-out by line-merge over `//` / `///`
  (CRITICAL).** A parenthesised/bracketed group or an `enum` / `type`
  list that contained an end-of-line `//` (or `///` XMLDoc) comment was
  flattened onto one physical line by the structural emitter
  (`InlineRenderRange` / `RenderParensBroken`), so every token after the
  comment -- following enum members, the closing `)`/`]`, `;`, the next
  argument -- was swallowed into the comment, silently destroying code
  that then failed to compile. The emitter now detects a line-comment
  token (`RangeHasLineComment`) anywhere in such a range and emits the
  group verbatim, preserving the source line breaks; reflow was already
  comment-safe. Affected multi-line argument/array lists and enum/type
  declarations with interleaved `//`, `///`, or `{$REGION}` comments.
- **`{$I}` / `{$INCLUDE}` directives no longer deleted (CRITICAL).**
  The bundled DelphiAST lexer silently drops include directives when no
  include handler is set (`TmwBasePasLex.Next`, `PtIncludeDirect` ->
  `Next`), so a reformat erased every `{$I jedi.inc}`-style line --
  flipping off the conditional symbols they define (project-wide
  build breakage from a single pass). YADF now shields true include
  directives before lexing and restores them afterward
  (`ShieldIncludeDirectives` / `UnshieldIncludeToken` in YADF.Tokens),
  so they round-trip verbatim and in place. IOCHECKS toggles
  (`{$I+}` / `{$I-}`) are correctly left untouched.
- Regression corpus: `Test/Cases/bug_comment_merge_arglist.pas`,
  `bug_enum_comment_merge.pas`, `bug_include_directive.pas` (synthetic,
  no proprietary source). Updated golden `Result/includefile.pas` --
  the prior snapshot had encoded the include-dropping bug.

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
