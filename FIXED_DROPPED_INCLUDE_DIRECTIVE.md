> **STATUS: RESOLVED (2026-05-15, YADF 1.0.1.16).** True `{$I}` / `{$INCLUDE}`
> directives are now shielded before lexing and restored afterward
> (`ShieldIncludeDirectives` / `UnshieldIncludeToken` in `YADF.Tokens`), so
> they round-trip verbatim and in place; IOCHECKS toggles (`{$I+}`/`{$I-}`)
> are left untouched. Regression test: `Test/Cases/bug_include_directive.pas`.
> Kept for history / regression reference only.

# YADF BUG (CRITICAL) — `{$I include}` compiler directives between `interface` and `uses` are silently deleted

**Reported by:** Claude Opus, Micronite ORM3 project, 2026-05-15
**Severity:** CRITICAL — silent removal of conditional-compilation include files. Distinct from `BUG_LINE_MERGE_OVER_COMMENT.md` (different code path, different symptom). Found in the same `yadf <proj>.dproj --b` run.

---

## Symptom

When a unit has `{$I ...}` include directives positioned **after `interface` and before the `uses` clause**, YADF **deletes them entirely** while reformatting the surrounding area (the uses clause is rewritten to comma-first; the `{$I}` lines vanish in the process).

Those include files define the project's conditional-compilation symbols. Removing them silently flips `{$IFDEF ...}` regions off, so code that *was* compiled is now excluded — typically surfacing as **"E2065: Unsatisfied forward or external declaration"** for routines whose bodies live inside a now-dead `{$IFDEF}` block.

## Evidence — `C:\Projects\DB\ORM3\COMMON\MStreams.pas`

Original (correct, `MStreams.pas.BCK1`, lines 11-16):

```pascal
interface

{$I ..\JEDI.inc}
{$I ..\INC.inc}

uses
  SYSTEM.Classes,
```

After `yadf --b` (lines 11-14) — both `{$I}` lines GONE:

```pascal
interface

uses
  SYSTEM.Classes
  , SYSTEM.SysUtils
```

`..\JEDI.inc` / `..\INC.inc` define `SUPPORTSENCODING` (among many project symbols). With them gone, this block later in the unit is excluded:

```pascal
{$IFDEF SUPPORTSENCODING}
procedure WriteBOM(const AStream: TStream; const AEncoding: TEncoding); ... 
function ReadBOM(...): TEncoding; ...
{$ENDIF}
```

but the interface still forward-declares `WriteBOM`/`ReadBOM`, so:

```
MStreams.pas(341): error E2065: Unsatisfied forward or external declaration: 'WriteBOM'
MStreams.pas(342..344): error E2065: Unsatisfied forward or external declaration: 'ReadBOM'
IuMicObject.pas(16): error F2063: Could not compile used unit 'MStreams.pas'
```

(A secondary visible symptom: the implementation-section routines below the lost define were re-indented as if nested — YADF's structural model also drifted once the define disappeared. The indentation is cosmetic; the deleted `{$I}` is the cause.)

## Why this is especially dangerous

- **Silent.** YADF reported `--- 503 ok, 0 failed ---`. No warning that directives were dropped.
- **Project-wide blast radius.** `{$I jedi.inc}`-style includes between `interface` and `uses` are a standard Delphi idiom (JEDI/JCL/JVCL, DUnitX, many libraries). Any such unit loses its conditional symbols.
- **Misleading errors.** The failure (`Unsatisfied forward declaration`) points at the *forward decl line*, far from the deleted directive at the top of the unit. Hard to diagnose without a diff against the backup.

## Root cause hypothesis

The uses-clause reformatter (comma-first rewrite) appears to treat the span between `interface` and the end of `uses` as a region it owns, and rebuilds it from the parsed unit list — discarding any `{$I}` / compiler directives that were interleaved in that span. Likely the parser attaches `{$I}` as trivia that the uses-clause emitter does not re-emit.

## Suggested fix

- Treat `{$I ...}`, `{$INCLUDE ...}`, and all `{$...}` compiler directives as **first-class, position-preserving tokens** — never droppable, anywhere, including the `interface`→`uses` gap and inside/around the uses list.
- When rewriting the uses clause, emit any directives that appeared before/within/after it in their original relative position.
- Add an invariant check (see `BUG_LINE_MERGE_OVER_COMMENT.md` "Impact note"): the count and text of `{$...}` directives must be identical pre/post format; refuse to overwrite on mismatch.

### Regression test

A unit shaped exactly like:

```pascal
unit U;
interface
{$I jedi.inc}
{$I extra.inc}
uses System.SysUtils;
{$IFDEF SOMESYM}
procedure P;
{$ENDIF}
implementation
{$IFDEF SOMESYM}
procedure P; begin end;
{$ENDIF}
end.
```

Assert both `{$I}` lines survive verbatim and in place.

## Repro material

- Broken: `C:\Projects\YADF\bug-repro\MStreams.pas.yadf-broken`
- Correct: `C:\Projects\YADF\bug-repro\MStreams.pas.correct`
- `diff` them; the first hunk (`13,15d12`) is the deleted `{$I}` lines.

## Companion reports from the same run

- `BUG_LINE_MERGE_OVER_COMMENT.md` — line-merger collapses enums/declarations onto `//`/`///` comment lines (destroyed `MSCTYPES.PAS`).
- `BUG_COMMENT_MERGE.md` — earlier-found instance of the merge-over-comment defect in multi-line argument lists.

These three are likely the dominant defects; a single full-project pass on a ~500-unit Delphi codebase produced project-wide breakage with a false "0 failed" report. Recommend a hard `--verify` (re-lex/parse round-trip with structure + directive + comment invariants) before YADF is used in bulk again.
