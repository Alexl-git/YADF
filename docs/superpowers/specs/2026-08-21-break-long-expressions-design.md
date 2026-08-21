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
- It skips string literals and comment interiors, so a break never lands inside
  one.

### Correction: the scanner does NOT filter operators by depth

Despite its name, `FindOperatorPositionsAtTopLevel` returns operator positions at
**every** nesting depth. At `YADF.Layout.pas:5643-5659` the `(`/`)` branch calls
`St.StepCode` to maintain the depth counter, but the `AddIfWord` calls for
`or` / `and` / `xor` -- and the `+` / `-` branch -- never consult `St.Depth`.
Only the comma branch checks depth, and it requires `Depth > 0`.

Confirmed by running the current build at `--max-len 60`: a long first component
was broken at an `and` **inside** its parentheses --

```pascal
  if (AlphaFlagIsLong and BetaFlagIsLong
    and GammaFlagIsLong and DeltaFlagIsLong)
    or (GammaFlagIsLong and DeltaFlagIsLong) then
```

This works today only because the greedy rule happens to prefer the rightmost
fitting position, which is usually the outermost operator. The non-greedy rule
has no such luck: breaking at *every* returned position would shatter
parenthesised groups that should stay whole.

**Therefore depth filtering is new work, not existing behaviour.** A companion
scanner that returns only depth-0 operator positions is required, and it is the
first thing the implementation must build.

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
BreakComponents(Line, BaseIndent, Level, Depth):
  if Length(Line) <= MaxLen: emit Line; return
  Positions := operator positions in Line at bracket depth EXACTLY Depth
  drop any position at or before the line's first token
      (a continuation already begins with its own operator; that
       leading operator is not a boundary)
  if Positions is empty: emit Line unchanged; return   (atomic)
  Split Line at EVERY position -> Head, C1 .. Cn
  emit Head at its current indent
  for each Ci:
    Ind := BaseIndent + (Level + 1) * AOpts.Indent
    if Length(Ind + Ci) <= MaxLen: emit Ind + Ci
    else BreakComponents(Ind + Ci, BaseIndent, Level + 1, Depth + 1)
```

**`Depth` is what makes the recursion work, and it is not optional.**
Components are delimited by *every* boundary at their own depth, so by
construction no further boundary remains **inside** one -- rescanning a
component at the same depth finds nothing and the recursive branch would be
unreachable dead code. A component's own sub-components live one bracket level
in: the parts of `or (A and B)` are `A` and `B`. So breaking a component that
still overflows means rescanning it at `Depth + 1`, while rendering one indent
level further in at `Level + 1`. Bracket depth and indent depth advance
together but measure different things.

This was found by running the built code: with a fixed depth of 0 the recursion
never fired, and an over-long component fell through to the greedy fallback,
which does not filter depth and split **inside** a parenthesised group.

### Which positions count as component boundaries

A new scanner, `FindComponentBoundaries`, returns **only depth-0 operator
positions** -- `and`, `or`, `xor`, `+`, `-` at bracket depth 0. It is a
depth-filtered sibling of the existing scanner, not a replacement: the existing
one stays exactly as it is and continues to serve the greedy path when the option
is off.

The two candidate kinds must NOT be treated alike under the non-greedy rule:

- **Depth-0 operators** delimit components. The non-greedy rule breaks at every
  one of them.
- **Commas at depth > 0** -- the existing scanner adds these
  (`YADF.Layout.pas:5660` requires `St.Depth > 0`) so an argument list can be
  broken when nothing else is available. `FindComponentBoundaries` does **not**
  return them at all, and the new breaker never consults them.

**A piece with no boundary at its current depth is ATOMIC: emit it unchanged and
accept the overflow.** It must NOT fall through to `BreakLineByOperators`. That
function does not filter by depth, so it would split inside a parenthesised
group -- destroying exactly the grouping this option exists to preserve. An
over-long line is a cosmetic problem; a shattered group is a correctness one.

An earlier draft of this spec said the opposite in this section while the
algorithm above said "emit unchanged". The contradiction reached the
implementation and produced a shattered group on the first run.

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

## Control headers

**All three control headers have their conditions broken** by the component rule
above -- there is nothing special about them, they are simply over-long lines:

- `if <condition> then`
- `while <condition> do`
- `until <condition>`

They differ only in what happens to the trailing keyword.

### Trailing keyword placement

`then` and `do` move to their own line at **exactly the indent of the header
keyword that introduced them**: `then` aligns with its `if`, `do` aligns with its
`while`. Not the component indent, not the body indent -- the header's own
column, so the keyword brackets the condition visually.

```pascal
if (Aa)
  or (Bb)
  or (VeryLongConditionNameThatGoesOnAndOnForAges
    and Aa)
then
  DoSomething;

while (Aa)
  or (Bb)
do
  Step;
```

`until` has **no trailing keyword** -- it LEADS its condition rather than
following it -- so there is nothing to move. Its condition is still broken into
components exactly like the other two:

```pascal
repeat
  Step;
until (Aa)
  or (Bb)
  or (VeryLongConditionNameThatGoesOnAndOnForAges
    and Aa);
```

Note the terminating `;` stays on the final component line, since it closes the
statement rather than introducing a body.

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
- `YADF.Layout.pas` -- depth-filtered `FindComponentBoundaries` scanner;
  recursive component breaker beside `BreakLineByOperators`; trailing-keyword
  split; branch in `BreakLongLines`. The existing scanner and greedy breaker are
  left untouched and still serve the option-off path.
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
- `then` on its own line, at exactly the same column as its `if`
- `do` on its own line, at exactly the same column as its `while`
- a long `until` condition broken into components, with `until` keeping its
  leading position and the terminating `;` on the final component line
- a line at or under `MaxLen` left completely untouched
- option OFF reproducing today's greedy output exactly

The `then` / `do` column assertions are the load-bearing ones: they are what
`ReindentByDepth` is most likely to get wrong, since a lone keyword line looks
like a statement to an indent pass that works on depth alone.

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
