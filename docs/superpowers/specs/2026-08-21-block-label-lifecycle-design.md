# Block-label lifecycle -- measure post-break, add AND remove

Date: 2026-08-21
Status: approved design, not yet implemented
Author: design session with the maintainer

## Motivation

Two defects in `LabelLongBlocks`, one of which blocks defaulting
`BreakLongExpressions` to True.

### Defect 1 -- non-idempotent (blocker)

Labelling happens in `WalkGroup` during the structural token walk, using
`CurLine - StartLine`. That runs **before** `BreakLongLines`, so it measures a
line count the reader never sees.

Turn `BreakLongExpressions` on and format `Test\Cases\overflow_expression.pas`
twice:

```
pass 1:  end;
pass 2:  end; // procedure
```

Pass 1 measures the block pre-break (under `LabelMinLines`, no label), then
breaking adds lines. Pass 2 reads the already-broken file, measures over the
threshold, and adds the marker. Formatting twice yields different files.

The greedy breaker does not trip this (verified: idempotent) because it adds far
fewer lines. Smart breakup adds one line per component, so blocks cross the
threshold routinely. This is why the option currently ships default-off.

### Defect 2 -- stale markers are never cleaned up

Labelling only ever ADDS. A block shortened below `LabelMinLines` -- by
`CollapseShortBlocks`, by reflow, or by the author deleting code -- keeps its
`// procedure` marker permanently, now claiming a length the block no longer has.

## Design

### Rule 1: measure the final shape

Move the label decision out of the token walk and into a **post-pass over the
final line-broken text**, after every pass that changes line counts
(`BreakLongLines`, `ReflowLineBreaks`, `CollapseShortBlocks`, `JoinShortCaseAlts`).

Both runs then measure the same shape, which makes the pass idempotent by
construction rather than by luck.

### Rule 2: add and remove, never rewrite

- Block spans >= `LabelMinLines` and carries no label -> **add** ` // <keyword>`.
- Block spans < `LabelMinLines` and carries an exact-match label -> **remove** it.
- Block carries a label whose text is anything else -> **leave it alone**.

Deliberately NOT re-derived: a marker that says `// while` on a block that is now
a `for` is left as-is. Rewriting churns files where the wording may have been
adjusted by hand, and the maintainer ruled against it.

### Rule 3: remove only what this pass would itself have written

A trailing comment is eligible for removal only when its text is **exactly**
`// ` + `FindBlockLabel(<this block>)` -- the keyword the pass would generate for
**this specific `end`** -- and nothing more.

It is NOT enough for the text to be `// ` plus *some* keyword from the set. If
the `end` closes a `while`, only `// while` is removable; `// procedure` and
`// if` on that same `end` are left alone. A marker naming a different construct
is either an author's note or a stale artefact of an edit we did not make, and
in both cases it is not ours to delete.

Stated as one invariant: **the pass never removes a comment it would not itself
have written for that exact block.** Add and remove become symmetric --
`FindBlockLabel` is the single source of truth for both.

Everything else is untouchable. All of these are left alone:

| Comment | Why it is kept |
|---|---|
| `end; // procedure -- see ticket 42` | trailing prose after the keyword |
| `end; //procedure` | no space after `//` |
| `end; { procedure }` | brace comment, not `//` |
| `end; // TODO -oYADF ...` | not a label at all |
| `end; // procedure` on a `while` block | keyword does not match this block |

The sixteen keywords `FindBlockLabel` can return are `record case try asm object
else procedure function constructor destructor while for if initialization
finalization begin` -- but membership in that set is necessary, not sufficient.
The match is against the value computed for the block in hand.

## The content-guard exception

`YADF.Guard` requires every input comment to survive to the output. Formatter-
ADDED comments are allowed (ordered-subsequence), dropped ones are rejected --
`GuardTest` asserts this directly (`ok - dropped comment rejected`). So removal
as designed would make `FormatPreservesContent` DECLINE the whole file.

A narrow exception is therefore required, in the same spirit as the
`AAllowStringDuplication` relaxation `BreakCaseLabels` needed.

**Scope of the exception -- deliberately minimal:**

- It applies **only** to comments matching Rule 3 exactly.
- It permits **omission only**. Altering a comment, reordering comments, or
  dropping any other comment stays rejected.
- Directives and string literals are untouched by it and stay strict.
- It is gated on `LabelLongBlocks` being ON. With the option off, nothing
  generates or removes labels, so the guard stays fully strict.

Implementation shape: `FormatPreservesContent` gains a parameter alongside
`AAllowStringDuplication` -- e.g. `AAllowLabelRemoval` -- and when set, an
original comment that is missing from the formatted stream is tolerated **iff**
it matches Rule 3. Every other missing comment still fails, with its existing
reason string.

The relaxation must be proven not to widen: a `GuardTest` case must show that a
dropped NON-label comment is still rejected while `AAllowLabelRemoval` is on.

## Interaction with `BreakLongExpressions`

Rule 1 alone unblocks the default flip. Rules 2 and 3 and the guard exception
address Defect 2 and are independently useful, but are not required for
idempotency.

If the implementation has to be split, **Rule 1 ships first** and
`BreakLongExpressions` defaults to True on the back of it.

## Testing

- **Idempotency:** `Test\Cases\overflow_expression.pas` with
  `BreakLongExpressions` ON must be a fixed point. This is the regression that
  motivated the work.
- **Add:** a block crossing `LabelMinLines` only after breaking gets its label on
  pass 1, not pass 2.
- **Remove:** a block with an exact-match label, shrunk below the threshold,
  loses it.
- **Leave alone (each its own case):** `// procedure -- see ticket 42`,
  `//procedure`, `{ procedure }`, `// TODO -oYADF ...`, and -- the case that
  matters most -- `// procedure` sitting on an `end` that closes a `while`,
  which must survive untouched even though `procedure` is in the keyword set.
- **Guard:** with `AAllowLabelRemoval` on, a dropped exact-match label passes and
  a dropped ordinary comment still fails with its reason.
- **Round-trip:** `--check` passes on output that removed a label.
- 83 goldens byte-identical with `LabelLongBlocks` at its current default.

## Rejected alternatives

- **Re-derive marker text every run.** More correct, but rewrites markers in
  files where the wording may be deliberate. Maintainer ruled against it.
- **Relax the guard generally for comment removal.** Would let any comment-
  dropping bug through silently. The exception is exact-match-only for that
  reason.
- **Count logical rather than physical lines in the walker.** Does not fix it:
  pass 2's walker still emits from an input that already carries the breaks.
- **Leave labelling alone and keep `BreakLongExpressions` default-off.** Punts a
  known non-idempotency onto every user who ticks the box, which the maintainer
  explicitly rejected -- users will choose options against our advice, so the
  combination must work.
