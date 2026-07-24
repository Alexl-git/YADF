# Design spec: Join routine headers onto one line

Date: 2026-07-24
Status: approved (brainstorm), pending implementation plan
Branch context: experiment/autodoc-format (ships together with the branch WIP)

## Problem

YADF's line reflow (`ReflowLineBreaks`) is a conservative line *joiner*, not a
parameter re-packer. It merges physical line N into N+1 only when line N does not
end in a structural terminator; `CurBlocksMerge` returns True the moment a line
ends in `;` (YADF.Layout.pas, the `if R[Length(R)] = ';' then Exit(True)` rule).

A routine header whose parameter list the source split across lines puts a param
separator `;` at end-of-line:

```
function TPipeSessionBuilder.HandleComputeSchedule(const APayload: TBytes;
  AThreadStorage: IThreadStorage; ASessionCtx: ISessionContext;
  out ARspCmd: TCommandID; out ARspPayload: TBytes): Boolean;
```

The reflow cannot tell a param-separator `;` (inside an open paren) from a
statement terminator, so it refuses every merge and the source's 3-line split
survives verbatim. `MaxLen` (default 180) never gets a chance to act -- the
one-line form is ~196 chars, but even a 2-line pack is never attempted because
no merge is ever considered eligible.

## Goal

Collapse a routine header the source split across lines back onto ONE line. If
the joined line exceeds `MaxLen`, greedy-pack it at parameter separators (the
inverse of the example above). This is the "join" half of an eventual three-way
choice (Preserve / Join / Explode); the "Explode" (one param per line) mode is a
**later** feature that will reuse this feature's header-detection logic.

## Scope

IN:
- Routine header declarations: `function`, `procedure`, `constructor`,
  `destructor`, `operator`, and their `class` forms (`class function`, etc.).
- BOTH the interface-section forward declaration AND the implementation header,
  formatted identically (per user: "the definition should match the
  implementation part").
- Nested / local routines.
- Procedure-type declarations: `type X = procedure(...) of object;`,
  `= function(...): T;`, `reference to procedure/function(...)`.

OUT (explicitly not touched):
- Multi-line CALL argument lists, array/set literals, any other parenthesised
  list. Headers only.
- Directives that the source split onto their OWN separate line
  (`function Foo: Integer;` / newline / `virtual; abstract;`). Directives already
  on the header's last physical line ride along naturally; separately-split
  directives are left alone in v1 (a later-feature concern).
- The future "Explode" (one param per line) mode.

## On/off and interactions (confirmed decisions)

- **Always-on standard behavior.** No INI key, no GUI/CLI option, no
  `TYadfOptions` field. YADF always joins routine headers as canonical
  formatting.
- **Runs independently of `--no-reflow`.** Header-joining is its own standard
  behavior, not part of long-line reflow, so it fires even when
  `ReflowLines = False`.
- **Golden blast radius accepted.** Any existing golden fixture containing a
  multi-line routine header will be re-flowed to one line and must be
  re-blessed. The golden suite identifies exactly which.

## The detection rule (load-bearing)

The reliable signal is NOT the trailing `;` -- it is **paren depth**. A split
header always breaks while an opening `(` is still unclosed:

```
function TFoo.Bar(const A: TBytes;   ( still OPEN at EOL  -> continuation follows
  B: IThing; C: ISession;            depth > 0            -> keep joining
  out D: TCmd): Boolean;             ) closes, ; at depth 0 -> header ends
```

Algorithm for the new pass `JoinRoutineHeaders`:

1. **Start detection (gates out plain calls).** A logical header begins at a
   physical line whose first significant token(s) are a header keyword
   (`function`/`procedure`/`constructor`/`destructor`/`operator`, optionally
   preceded by `class`), OR the line is a procedure-type declaration
   (`... = procedure(` / `... = function(` / `reference to procedure|function`).
   The check is on the leading token only, using the existing scanner so
   keywords inside strings/comments do not trigger.
2. **Continuation accumulation.** From the start line, track paren/bracket depth
   with the existing `TLineScanState` scanner (so `(`/`)`/`;` inside string
   literals or comments are ignored). Accumulate physical lines **while depth > 0**,
   then up to and including the terminating `;` at depth 0. That terminating `;`
   ends the logical header.
3. **Join.** Concatenate the accumulated physical lines into one line: trim each,
   join with single spaces, preserving the leading indent of the start line.
   Token text is copied verbatim (casing fidelity -- do not re-case).
4. **Overflow wrap.** If the joined line length > `MaxLen`, run it through the
   existing `BreakLineByOperators` greedy wrapper (rightmost separator <= MaxLen,
   continuation indent = leading indent + `Indent`). One line when it fits, more
   when it does not.
5. **Re-indent.** Follow the pass with `ReindentByDepth` so the (possibly
   re-wrapped) header sits at correct structural depth.

Why depth-driven and not `;`-driven: a real statement terminator cannot occur
inside an open paren, so "join while depth > 0" is unambiguous and cannot merge
across statement boundaries. Gating on the leading header keyword is what keeps
multi-line calls (which also sit inside open parens) out of scope.

## Pipeline placement

New Stage-3 string pass, in the same slot as `BreakControlBodies`
(YADF.Layout.pas ~line 4900): after the reflow/pack block, before the Stage-4
alignment passes (`SplitMultiVarDeclarations`, `AlignByAnchor`, ...). Immediately
followed by `ReindentByDepth`.

Rationale: it must act on the settled line shape (post-reflow) and before
alignment, because it changes line adjacency. Being placed before alignment, a
one-line header presents no `:`/`=` columns for the aligners to disturb.

## Properties

- **Content-neutral / Guard-safe.** Only whitespace and line breaks change; token
  order and text are preserved, so the Stage-6 `YADF.Guard` content-preservation
  net passes.
- **Idempotent.** A header already on one line (<= MaxLen) has no open paren at
  EOL and no depth>0 continuation -> untouched. A header greedy-wrapped because
  it exceeds MaxLen re-joins (its continuations are inside an open paren) and
  re-wraps to the identical deterministic greedy shape -> stable second run.
- **Casing fidelity.** Verbatim token copy respects `LowercaseKeywords = False`
  (same fix class as the standalone-`else` copy in BreakControlBodies).

## Testing

New `Test/test_join_headers.ps1` (mirrors `Test/test_break_control.ps1`):

1. 3-line header -> 1 line (the motivating case).
2. Over-MaxLen header -> greedy-packed onto >1 line.
3. Idempotency: running the output back through is a no-op.
4. Casing fidelity with `LowercaseKeywords = False`.
5. Interface-section forward decl with trailing directives (`; virtual;`).
6. Procedure-type declaration (`= procedure(...) of object;`).
7. Nested / local routine header.
8. NEGATIVE: a multi-line CALL argument list must survive unchanged.
9. dcc64 compile-gate: the joined/wrapped output is valid Delphi.

Plus the full golden suite re-run; re-bless fixtures whose headers were
multi-line.

## Files touched

- `YADF.Layout.pas` -- new `JoinRoutineHeaders` pass (+ start-detection and
  depth-accumulation helpers), wiring at ~line 4904. Purely additive.
- `Test/test_join_headers.ps1` -- new.
- `CHANGELOG.md` -- entry.
- Re-blessed golden fixtures as the suite dictates.
- No `YADF.Options.pas` / `YadfMain.pas` / GUI changes (no option).

## Out of scope / later

- "Explode" mode (one param per line), as a Preserve/Join/Explode choice. Will
  reuse the start-detection + depth-accumulation helpers built here.
- Joining directives that the source split onto their own line.
