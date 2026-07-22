# Break control-statement bodies onto their own line -- design

Date: 2026-07-22
Status: approved (brainstorming), pending implementation plan
Author: Alexander Liberov

## Problem

YADF never proactively *splits* a control statement whose body already fits on
one line. A source line such as

```pascal
while (k >= 0) and (Outp[k].Kind = ptSpace) do Dec(k);
```

is left intact because the reflow engine only *merges* adjacent lines (and only
*splits* lines that exceed `MaxLen`). Some house styles want the body of a
control statement always on its own indented line:

```pascal
while (k >= 0) and (Outp[k].Kind = ptSpace) do
  Dec(k);
```

There is no option for this today. `PackShortBodies` does the opposite (pulls a
short body *up* onto its header); this feature is its inverse.

## Scope: three independent options

Per-construct control, so callers can opt in exactly where they want it. All
three are `Boolean`, all default **False** (existing output is unchanged unless
explicitly enabled).

| Option          | Covers                     | Header keyword ends in |
|-----------------|----------------------------|------------------------|
| `BreakLoopBody` | `for ... do`, `while ... do` | `do`                 |
| `BreakWithBody` | `with ... do`              | `do`                   |
| `BreakIfBody`   | `if ... then`, `else`      | `then` / `else`        |

`with` is deliberately separate from the loops (it is not a loop). `case` arms
are already covered by the existing `BreakCaseLabels` / `PackShortBodies` and are
out of scope here.

## Non-goals

- **`begin` blocks are never touched.** If the body is `begin` (Allman-style
  `begin`-on-its-own-line), the line is left alone. Moving a `begin` to its own
  line is a separate, much larger concern with no existing option.
- **Nested control-header bodies are left alone.** If the body itself begins with
  a control keyword (`if`/`while`/`for`/`with`/`case`/`repeat`/`try`/`begin`/
  `asm`), the line is not split -- e.g. `while A do while B do X;` is preserved.
  This matches the conservative philosophy of `PackShortBodies` /
  `CollapseShortBlocks` and avoids ambiguous half-splits. May be relaxed later.
- Not a reformatter of already-multi-line control statements: those are already
  handled by the existing indent engine. This pass only acts on *single-line*
  control statements.

## Approach A (selected): one new string-level split pass

Add a single function to `YADF.Layout.pas`:

```pascal
function BreakControlBodies(const S: string; const AOpts: TYadfOptions): string;
```

It is the structural mirror of the existing `CollapseShortBlocks` (which *joins*
a short `begin..end` body). It walks the lines and, for each line that is a
*complete single-line* control statement whose governing flag is on and whose
body qualifies, inserts CRLF break(s) so the body drops to its own line. A
following `ReindentByDepth` gives the freed body its `+1` indent -- exactly how
the reflow and collapse paths already re-indent after they change line structure.

### Rejected alternatives

- **B -- invert the merge logic inside `ReflowLineBreaks`.** That function is a
  *merge* engine wound tightly around the fit-within-`MaxLen` decision and is the
  most heavily golden-tested pass. Teaching it to also *split* couples two
  opposite operations and risks broad regressions.
- **C -- emit the break in the structural token emitter (`WalkGroup`, Stage 2).**
  AST-precise but far deeper and riskier; the emitter feeds every downstream
  pass, and every comparable option already lives in the string-pass layer.

## Algorithm

For each line (skipping block-comment-locked lines via
`ComputeBlockCommentLock`, as the sibling passes do):

1. Scan the line left-to-right with the shared `TLineScanState` /
   `SkipNonCode` state machine so `do` / `then` / `else` inside a string literal
   or comment are ignored, and so trailing `//` or open `{ ... }` disqualify the
   line (never split a line carrying a top-level line comment or an open block
   comment -- same guard as `CurBlocksMerge`).
2. Classify the line by its leading control keyword and the enabled flags:
   - `for` / `while` -> eligible iff `BreakLoopBody`.
   - `with` -> eligible iff `BreakWithBody`.
   - `if` -> eligible iff `BreakIfBody`.
   - anything else -> leave unchanged.
3. Find the split keyword(s) at **top level** (paren/bracket depth 0, outside
   strings/comments):
   - Loops / `with`: the header-terminating `do`. The body is everything after
     it. Break after `do`.
   - `if`: the header-terminating `then`, and any top-level `else`. Break after
     `then`, before `else`, and after `else`.
4. **Body qualification** (all split points): the body segment must be a single
   simple statement -- non-empty, and its first word must NOT be a control-header
   keyword (`if`/`while`/`for`/`with`/`case`/`repeat`/`try`/`begin`/`asm`). If any
   body segment fails, the whole line is left unchanged (no partial split).
5. **`else if` chains stay glued.** When an `else` is immediately followed
   (skipping spaces) by `if`, keep `else if ... then` together on one line and
   continue the split from that inner `then`. Applied recursively so
   `if A then B else if C then D else E;` becomes:

   ```pascal
   if A then
     B
   else if C then
     D
   else
     E;
   ```
6. Emit the broken lines with the header's original leading indentation on the
   header/`else` lines; body lines get a provisional indent that
   `ReindentByDepth` immediately normalises.

### Worked examples

```
Input:   while (k >= 0) and (Outp[k].Kind = ptSpace) do Dec(k);
Output:  while (k >= 0) and (Outp[k].Kind = ptSpace) do
           Dec(k);

Input:   for i := 0 to High(Src) do Sum := Sum + Src[i];
Output:  for i := 0 to High(Src) do
           Sum := Sum + Src[i];

Input:   with Rec do X := 1;
Output:  with Rec do
           X := 1;

Input:   if X then DoIt else DoOther;
Output:  if X then
           DoIt
         else
           DoOther;

Left unchanged (begin body):        while A do begin Inc(X); end;
Left unchanged (nested header):     while A do while B do X;
Left unchanged (has line comment):  if X then DoIt; // note
```

## Pipeline placement

In `FormatSource`, Stage 3, immediately after the reflow / pack `if..else`
block and before the Stage-4 alignment passes:

```
... ReflowLineBreaks / JoinShortCaseAlts block (unchanged) ...
if AOpts.BreakLoopBody or AOpts.BreakWithBody or AOpts.BreakIfBody then
begin
  Result := BreakControlBodies(Result, AOpts);
  Result := ReindentByDepth(Result, AOpts.Indent, AOpts.IndentComments);
end;
... CollapseBlankLines, then Stage-4 alignment ...
```

Rationale:
- **Before alignment** because splitting changes which lines are adjacent, and
  the alignment passes key on runs of adjacent similar lines.
- **After reflow** so it runs on the settled line shape. It also runs when
  `ReflowLines` is off (it is gated only on its own three flags).
- `CollapseShortBlocks` (final pass) only folds `begin..end` bodies, which this
  pass never produces, so the two never fight.

## Interaction with `PackShortBodies`

`PackShortBodies` packs a short body *up*; these options split it *down*. They
are inverses. Precedence is **split wins**: `BreakControlBodies` runs *after* the
reflow/pack block, so for a construct whose Break* flag is on, the final shape is
split regardless of `PackShortBodies`. This is stable across repeated formats
(idempotent): pack-then-split yields the same split output every run.

## Idempotency and the content Guard

- **Idempotent:** after a split the body is already on its own line; a second run
  finds nothing to split (single-line classification fails) -- no-op.
- **Content-neutral:** the pass only inserts CRLF + leading whitespace; it never
  adds, drops, or edits a string literal, comment, or compiler directive. The
  Stage-6 `FormatPreservesContent` Guard therefore passes with no new tolerance
  exception (contrast `BreakCaseLabels`, which duplicates arm bodies and needs
  the duplication tolerance).

## Surfaces and wiring

| Surface | Wiring | Effort |
|---|---|---|
| INI read/write + `yadf.ini` template | iterates `OptionTable` | auto (0 lines) |
| YADFSetup playground UI | shared `TYadfOptionsFrame`, iterates `OptionTable` | auto |
| YADFOT IDE Options page | same shared frame | auto |
| `TYadfOptions` fields + `DefaultOptions` + `OptionTable` entries | manual | 3 fields, 3 defaults, 3 `MakeOpt` entries |
| CLI flags + `--help` lines | hand-coded chain in `YadfMain.pas` | manual |

### Option-table entries

Three `MakeOpt` calls in the `Reflow & whitespace` group, `AffectsPreview :=
True` (they change formatting; the live preview reflects them), each with a
one-line hint. Names/captions:

- `BreakLoopBody` -- "Break loop body onto its own line"
- `BreakWithBody` -- "Break with body onto its own line"
- `BreakIfBody`   -- "Break if/then/else body onto its own line"

### CLI flags (in `YadfMain.pas`, mirroring `--pack-bodies`)

`--break-loop` / `--no-break-loop`, `--break-with` / `--no-break-with`,
`--break-if` / `--no-break-if`, each with a `--help` line showing the resolved
default (all `false`).

## Testing

- **New fixture(s)** under the golden/test fixtures dir: a unit exercising
  `for` / `while` / `with` / `if-then` / `if-then-else` / `else-if` chains, plus
  the left-unchanged cases (`begin` body, nested header, trailing line comment).
- **`Test\test_break_control.ps1`** (mirrors `test_break_case.ps1`): asserts each
  flag independently produces the expected split, that unrelated constructs are
  untouched, and that formatting the output a second time is stable (idempotent).
- **Compile gate:** the formatted fixture output must still compile via the
  existing dcc64 compile-the-output gate.
- **`OptionsTest.dpr`:** assert the three new keys round-trip through INI
  (write -> read -> equal) and appear in the template.
- **Existing goldens:** unchanged (all three default False), so no golden is
  re-blessed.

## Documentation

- `CHANGELOG.md`: one entry describing the three options.
- README option list is generated / mirrored from the table hints; update if it
  carries a hand-written option table.

## Open questions

None outstanding. Names, CLI inclusion, and the `begin`-untouched non-goal are
confirmed.
