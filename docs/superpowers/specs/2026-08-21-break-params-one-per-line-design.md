# BreakParamsOnePerLine -- one routine parameter per line

Date: 2026-08-21
Status: approved, not yet implemented
Author: design session with the maintainer

## Motivation

Users have asked for a vertical parameter list on routine declarations: one
parameter per line, as a deliberate style rather than as an overflow fallback.
YADF today has no way to produce that shape.

## Scope

**In scope:** parameter lists on *named routine declarations* --
`procedure`, `function`, `constructor`, `destructor`, `operator`, including
their `class` forms -- in the interface section, the implementation section,
and nested/local positions.

**Out of scope:**

- Call-site argument lists. `Foo(A, B, C)` is untouched.
- Inline anonymous `procedure(` / `function(` headers. These are expressions,
  not declarations; breaking them fights the surrounding argument layout.
- `property` declarations and their index parameters.

## Option surface

One new `Boolean` field on `TYadfOptions`, one `MakeOpt` entry in
`OptionTable`. Nothing else.

| | |
|---|---|
| Field / INI key | `BreakParamsOnePerLine` |
| Group | `Declarations` |
| Caption | `Break parameters one per line` |
| Kind | `okBool`, `AffectsPreview: True` |
| Default | `False` |
| CLI | `--break-params` / `--no-break-params` |

Default-off is load-bearing. It keeps all 83 existing golden baselines green
without rebaselining, so the new fixtures are the only thing exercising the
pass.

The `Tools > Options` checkbox appears in **both** hosts automatically:
`TYadfOptionsFrame` code-builds its controls by iterating
`YADF.Options.OptionTable` (`YADF.OptionsFrame.pas:763`), and YADFSetup
(`uYADFSetupMain`) and YADFOT (`YADFOT.Options`) share that frame. No UI code
is written in either host.

## Trigger

The pass fires on a routine header when all of the following hold:

1. `AOpts.BreakParamsOnePerLine` is on.
2. The header has a parameter list.
3. **After group splitting**, the list has 2 or more parameters.

Condition 3 is evaluated post-split by decision. `procedure Swap(var A, B:
Integer);` splits into two parameters and therefore **does** break. The
alternative -- counting groups, leaving `Swap` inline -- was considered and
rejected by the maintainer.

A header containing a `//` or `///` line comment anywhere is skipped whole,
matching the existing comment-safety doctrine at `YADF.Layout.pas:5249`.

## Rendering

The separator style is **not** a new option. It mirrors the existing
`UsesCommaLast`, so a file's uses clauses and its parameter lists share one
style knob and stay visually consistent.

### `UsesCommaLast = False` (default) -- separator-first

The analogue of the comma-first uses clause, whose `;` sits alone on its own
line. Here the closing `)` plays that role:

```pascal
function TMyClass.Copy(
    const ASrc: string
    ; const ADest: string
    ; AFlags: Integer
    ; out AErr: string
    ): Boolean;
```

### `UsesCommaLast = True` -- separator-last

The analogue of the comma-last uses clause, whose `;` rides the last unit's
line. Here the closer rides the last parameter's line:

```pascal
function TMyClass.Copy(
    const ASrc: string;
    const ADest: string;
    AFlags: Integer;
    out AErr: string): Boolean;
```

### Indentation

Parameters indent at `BaseCol + AOpts.Indent * 2`.

This deliberately deviates from `RenderUsesGroup`, which uses a single
`Indent` (`YADF.Layout.pas:3895`). With a single indent the parameters land in
the same column as the `begin` body directly beneath them. `RenderParensBroken`
already uses `* 2` for exactly this reason (`YADF.Layout.pas:5145`).

## The splitter

Within each parameter item, locate the **first top-level `:`** (depth 0 with
respect to `()` and `[]`). Depth tracking on `<>` is deliberately *not*
performed and is not needed: the pre-colon region contains only an optional
modifier, an optional bracketed attribute, identifiers, and commas. A `<` can
never legally appear there, so there is no generics-vs-less-than decision to
make. The first top-level `:` is always the name/type separator, because types
appear only after it. Everything before it is
`[const|var|out] Name1, Name2, ...`; everything from the `:` onward is the type
and any `= default`. Split on commas in the **pre-colon region only**,
repeating the modifier on each emitted line.

Confining the comma scan to the pre-colon region is the core safety property.
`A, B: TDictionary<string, Integer>` has a comma inside the *type*, which the
splitter never examines -- so the classic Delphi generics-vs-less-than
ambiguity cannot be got wrong here.

Untyped parameters (`var A, B`) have no top-level colon and split on names
alone, yielding `var A; var B`.

### Groups that are NOT split

These four cases keep the group intact on one line. The parameter list may
still break between *items*; only the group itself stays whole. An unsplit
group counts as **one** parameter for the 2+ threshold above -- so
`procedure Foo(const A, B: string = 'x');` is a single unsplit group, counts
as one parameter, and the header does not break at all.

1. **Attribute present** -- `[Ref] const A, B: TRec`. Duplicating an attribute
   is not content-neutral.
2. **Interior comment between names** -- `A, {why} B: Integer`. There is no
   correct line to put the comment on.
3. **`=` default value present.** This one is forced by the content guard.
   `procedure Foo(A, B: string = 'x')` would split into two copies of the
   literal `'x'`; `SameSequence` in `YADF.Guard.pas:242` compares string
   literals as an exact sequence and would reject the **entire file**, making
   YADF silently decline to format it. Refusing to split defaulted groups
   removes the failure mode regardless of whether the compiler even accepts
   that declaration.
4. **Unbalanced / unscannable header** -- bail out and emit verbatim.

### Content neutrality

Splitting duplicates the modifier keyword (`const`) and the type name
(`string`). Neither is a string literal, a comment, nor a compiler directive,
so `FormatPreservesContent` is unaffected -- **provided** rule 3 above holds.
The pass therefore does not need the `AAllowStringDuplication` relaxation that
`BreakCaseLabels` requires.

## Pipeline placement

Immediately after `JoinRoutineHeaders` (`YADF.Layout.pas:5551`), before
`CollapseBlankLines` and Stage-4 alignment.

This ordering is forced, not chosen. `JoinRoutineHeaders` is unconditional
("always-on standard behavior (no option)") and explicitly rejoins multi-line
routine headers onto one line, so any pass running earlier would simply be
undone. drag-lint confirms `JoinRoutineHeaders` has exactly one call site, so
this is a single-line insertion.

Running after it is also the better design: every header arrives already
normalised onto one line regardless of how the author wrote it, which makes the
new pass a pure function of the header text and therefore idempotent.

Landing before Stage 4 means the split parameter lines participate in
`AlignTypeColon`, aligning their `:` -- consistent with that option's own
description ("type / var / parameter blocks").

The pass emits its final indentation directly and requires no
`ReindentByDepth` afterwards, the same contract `JoinRoutineHeaders` documents.

## Files touched

- `YADF.Options.pas` -- record field, `DefaultOptions` line, `OptionTable` entry.
- `YADF.Layout.pas` -- new `BreakRoutineParams` pass + one call site at 5551.
- `YadfMain.pas` -- CLI flag parsing and the `--help` line.
- `Test\Cases\` -- new fixtures (below).
- `CHANGELOG.md`, `Demo\Sample.pas` -- showcase entry, matching how
  `CollapseShortBlocks` and `BreakCaseLabels` were documented.

No UI files. No new units.

## Testing

TDD: failing test first, then implement to green.

Fixtures in `Test\Cases`:

- separator-first rendering (`UsesCommaLast = False`)
- separator-last rendering (`UsesCommaLast = True`)
- grouped split with `const` / `var` / `out` modifier repetition
- generic type containing a comma (`TDictionary<string, Integer>`)
- untyped parameter group (`var A, B`)
- each of the four no-split fallbacks
- single-parameter header staying inline
- zero-parameter header untouched

Assertions beyond golden comparison:

- **Idempotency** -- formatting the output again is a fixed point.
- **Compile gate** -- output compiles, via the existing TestLib harness.
- **Regression** -- `Test\run_tests.ps1` stays 22/22 with the 83 existing
  goldens byte-identical, since the option defaults off.

## Open questions

None. All decisions above are settled.

## Rejected alternatives

- **Break only on `MaxLen` overflow.** That is an overflow fallback, not a
  style; it is not the feature that was asked for.
- **Reuse `RenderParensBroken` directly.** It splits on `ptComma` only
  (`CollectParensItems`, `YADF.Layout.pas:4039`) and hard-codes `,` when
  rejoining (`:5173`). A `;`-separated declaration list is seen as a single
  item and never breaks. A parameter-aware splitter is required.
- **A separate `ParamsSemicolonLast` option.** Redundant with `UsesCommaLast`
  and invites internally inconsistent files.
- **Aligning parameters under the open paren.** Column-anchored, so it fights
  `ReindentByDepth` and degrades once a long qualified name pushes the anchor
  past `AlignMaxColumn`.
