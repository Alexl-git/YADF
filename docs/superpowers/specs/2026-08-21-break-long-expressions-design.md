# BreakLongExpressions -- one component per line, operator leading

Date: 2026-08-21
Status: approved design, not yet implemented
Author: design session with the maintainer

## Motivation

When a long expression is broken across lines, the break should fall at the
expression's own structure: one top-level component per line, with the
connecting operator LEADING each continuation. That is the same doctrine YADF
already applies to uses clauses (comma-first) and to routine parameters
(`BreakParamsOnePerLine`, separator-first).

The maintainer's stated reason is practical, not cosmetic: when each component
owns a line, disabling one is a one-line edit -- comment it out or delete it --
with no re-wrapping by hand.

## What already works

`BreakLineByOperators` (`YADF.Layout.pas:5696`, nested inside `FormatSource`)
already does three of the necessary things, and this design keeps all three:

- It breaks at `and` / `or` / `xor` / `+` / `-`, and at `,` inside parentheses.
- The continuation line **starts with the operator** -- its own comment says
  "The continuation starts WITH the operator so the structure reads `op operand`
  at the new column."
- `FindOperatorPositionsAtTopLevel` tracks parenthesis depth, so
  `(A and B) or (C and D)` yields only the top-level `or` as a candidate. The
  parenthesised groups are already treated as indivisible components.

Measured today at `--max-len 60`, `if (A and B) or (C and D) then` produces:

```pascal
  if (AlphaFlagIsLong and BetaFlagIsLong)
    or (GammaFlagIsLong and DeltaFlagIsLong) then
```

That is the target shape apart from `then`.

## What is missing

Three gaps, each confirmed by running the current build.

### 1. The breaker is greedy

It picks "the rightmost break position that still fits", so multiple components
share a line. At `--max-len 50`:

```pascal
  if (Aa) or (Bb)
    or (VeryLongConditionNameThatGoesOnAndOnForAges
    and Aa) then
```

`(Aa) or (Bb)` were packed together. The maintainer wants **every** top-level
operator to break, one component per line, regardless of whether two would fit.
Greedy packing defeats the comment-out-a-line purpose.

### 2. Nesting is invisible

Every continuation lands at exactly one indent step, so the inner `and Aa`
(a sub-component of the third top-level component) is indented identically to
the outer `or`. The reader cannot tell which level a line belongs to.

### 3. The trailing control keyword rides the last line

`then` stays glued to the final component instead of sitting on its own line.

## Scope

**In scope:** every over-long line the existing `BreakLongLines` pass already
selects -- boolean conditions **and** arithmetic expressions alike. A long
`X := A + B + C;` breaks one term per line by the same rule.

**Out of scope:**

- Lines at or under `MaxLen`. The trigger is unchanged: overflow only.
- Lines inside block comments (already excluded by `ComputeBlockCommentLock`).
- Argument lists already broken structurally by `RenderParensBroken`, which runs
  earlier in the pipeline and one-per-lines them at the token level.

## Trigger

Unchanged from today: the line exceeds `AOpts.MaxLen`, is not comment-locked,
and the new option is on. A line that fits is never touched.

This was a deliberate choice by the maintainer over always-on breaking. With
`MaxLen=180` in the shipped `yadf.ini` it will fire rarely -- accepted, on the
grounds that when long identifiers do push a line over, the structured break is
worth having.

## The algorithm

Recursive, replacing the greedy loop when the option is on:

```
BreakComponents(Line, BaseIndent, Level):
  if Length(Line) <= MaxLen: emit Line; return
  Positions := top-level operator positions in Line   (existing scanner)
  if Positions is empty: emit Line unchanged; return  (nothing to break on)
  Split Line at EVERY position -> Head, C1 .. Cn
  emit Head at its current indent
  for each Ci:
    Ind := BaseIndent + (Level + 1) * AOpts.Indent
    if Length(Ind + Ci) <= MaxLen: emit Ind + Ci
    else BreakComponents(Ind + Ci, BaseIndent, Level + 1)
```

### Which positions count as component boundaries

`FindOperatorPositionsAtTopLevel` returns two different kinds of candidate, and
they must NOT be treated alike under the non-greedy rule:

- **Depth-0 operators** (`and`, `or`, `xor`, `+`, `-`). These delimit components.
  The non-greedy rule breaks at every one of them.
- **Commas at depth > 0** -- the scanner deliberately adds these
  (`YADF.Layout.pas:5660` requires `St.Depth > 0`), so an argument list can be
  broken when nothing else is available. These are **fallback** break points
  only. They are used when a component has no depth-0 operator and still
  overflows; they never participate in one-component-per-line splitting.

Without this distinction, "break at every position" would explode `Foo(A, B, C)`
into one argument per line, duplicating what `RenderParensBroken` already does
earlier in the pipeline and over-fragmenting ordinary calls.

The head segment -- the text before the first component boundary -- is emitted at
the line's existing indent and is not itself re-split; by construction it
contains no depth-0 operator.

Two properties follow directly and are the reason for this shape:

- **A component that fits is emitted whole**, parentheses included. Recursion
  descends only into components that still overflow, which is exactly the
  maintainer's "until all subcomponents fit".
- **Nesting depth maps to indent depth**, fixing gap 2. Level 1 components sit
  one step in, their over-long children two steps, and so on.

Indentation is a fixed multiple of `AOpts.Indent`, deliberately NOT aligned to
the opening parenthesis column. Column-anchored continuation fights
`ReindentByDepth` and degrades once a long qualified name pushes the anchor past
`AlignMaxColumn` -- the same reasoning that settled the parameter-list geometry.

## Trailing control keywords

After a header line is broken, a trailing `then` or `do` moves to its own line at
the **header's** indent:

```pascal
if (Aa)
  or (Bb)
  or (VeryLongConditionNameThatGoesOnAndOnForAges
    and Aa)
then
```

Applies to `if ... then` and `while ... do`. `repeat ... until` is excluded:
`until` LEADS its condition rather than trailing it, so there is nothing to move.

**Open for maintainer confirmation:** `while ... do` is included for consistency
with `if ... then`. Only `if ... then` was explicitly requested. If `do` should
stay on the last component line, that is a one-line change to the keyword list.

## Interactions

- **`BreakIfBody`** moves the then/else *body* onto its own line. This option
  moves the `then` *keyword*. They compose; neither reads the other's output.
- **`RenderParensBroken`** runs earlier and already one-per-lines overflowing
  argument lists at the token level. By the time this pass runs, such lists are
  usually already broken and under `MaxLen`, so it will not see them.
- **`ReindentByDepth`** must leave a lone `then` / `do` line at the header
  indent rather than treating it as a statement to indent. This is the main
  implementation risk and the first thing to test.

## Content neutrality

The pass inserts only CRLF and spaces -- it never reorders, duplicates, or drops
a token. `FormatPreservesContent` is therefore unaffected, and no
`AAllowStringDuplication` relaxation is needed.

## Option surface

| | |
|---|---|
| Field / INI key | `BreakLongExpressions` |
| Group | `Reflow & whitespace` |
| Caption | `Break long expressions one component per line` |
| Kind | `okBool`, `AffectsPreview: True` |
| Default | `False` |
| CLI | `--break-expr` / `--no-break-expr` |

Default-off is load-bearing twice over: it keeps all 83 golden baselines
byte-identical, and it leaves today's greedy breaker in place for anyone who
prefers it.

The checkbox reaches YADFSetup and YADFOT automatically via `OptionTable`
(`YADF.OptionsFrame.pas` code-builds from it), so no UI code is written.

## Files touched

- `YADF.Options.pas` -- record field, `DefaultOptions` line, `OptionTable` entry.
- `YADF.Layout.pas` -- recursive component breaker beside `BreakLineByOperators`;
  trailing-keyword split; branch in `BreakLongLines`.
- `YadfMain.pas` -- CLI flag parsing and two `--help` lines.
- `Test\test_break_expr.ps1` -- new.
- `CHANGELOG.md`, `Demo\Sample.pas` -- entry and showcase.

No new units. No UI files.

## Testing

TDD, failing test first. Fixtures must cover:

- a flat boolean condition, one component per line, operator leading
- a parenthesised condition -- groups stay whole, only the top-level operator breaks
- a component that itself overflows -- recursion, with the deeper indent visible
- an arithmetic expression (`X := A + B + C;`) breaking by the same rule
- **no greedy packing**: three top-level components where two would fit on one
  line must still produce three lines
- `then` and `do` on their own lines
- a line at or under `MaxLen` left completely untouched
- option OFF reproducing today's greedy output exactly

Plus idempotency (formatting twice is a fixed point), the `--check` content
round-trip, a `dcc64` compile gate on the broken output, and `Test\run_tests.ps1`
staying green with the 83 goldens byte-identical.

## Rejected alternatives

- **Always break, regardless of length.** Rejected by the maintainer: it would
  turn `if A and B and C then` into four lines at 24 characters.
- **Keep greedy packing.** Defeats the stated purpose -- a component sharing a
  line with another cannot be commented out independently.
- **Align continuations to the opening parenthesis.** Column-anchored, so it
  fights `ReindentByDepth` and breaks down past `AlignMaxColumn`.
- **Conditions only.** Widened to all expressions at the maintainer's direction;
  arithmetic benefits from the same one-term-per-line editability.
