> **STATUS: RESOLVED (2026-05-15, YADF 1.0.1.16).** The structural emitter now
> detects a line-comment token anywhere in a parenthesised/bracketed or
> enum/type range (`RangeHasLineComment`) and emits the group verbatim,
> preserving source line breaks; `//` and `///` are hard merge barriers in
> every reflow path. Regression test: `Test/Cases/bug_enum_comment_merge.pas`.
> Kept for history / regression reference only.

# YADF BUG (CRITICAL) — line-merger collapses multi-line declarations onto a line containing `//` or `///`, commenting out code

**Reported by:** Claude Opus, Micronite ORM3 project, 2026-05-15
**Severity:** CRITICAL — a single full-project format pass (`yadf <proj>.dproj --b`) destroyed `C:\Projects\DB\ORM3\COMMON\MSCTYPES.PAS` (the project's central enum/type/record-helper unit). 70+ compiler errors, compilation terminated. Every enum that has a trailing `//` comment or interleaved `///` XMLDoc is corrupted.
**Same root cause as** `BUG_COMMENT_MERGE.md` — this is the general, high-impact form. Fixing one should fix both. Recommend fixing here.

---

## The defect in one sentence

YADF's line-join / reflow logic merges several source lines into one physical line **without treating a `//` or `///` line comment as a hard barrier**. Because a line comment extends to physical end-of-line, every token merged *after* the comment (enum members, `)`, `;`, `{$ENDREGION}`, the next declaration) becomes comment text and vanishes.

## Evidence 1 — enum with a trailing `//` on the opening line (`TCharMClass`)

`MSCTYPES.PAS`, original (correct, from `.BCK1`):

```pascal
TCharMClass = (// 0 .. 9;
    CMC_Safety = 0, //
    CMC_None = 1,//
    Empty2 = 2, Empty3, Empty4, Empty5,
    CMC_Critical = 6, //
    Empty7,
    CMC_Major = 8, //
    CMC_Minor = 9 //
);
```

After `yadf --b` (broken — one physical line):

```pascal
TCharMClass = (// 0 .. 9; CMC_Safety = 0, // CMC_None = 1,// Empty2 = 2, Empty3, Empty4, Empty5, CMC_Critical = 6, // Empty7, CMC_Major = 8, // CMC_Minor = 9 // ); //
```

The opening token is `(` immediately followed by `// 0 .. 9;`. From that `//` to EOL is a comment. So the **entire enum body and its closing `);` are commented out**. The compiler sees `TCharMClass = (` with no members and no `)`.

## Evidence 2 — enum with interleaved `///` XMLDoc + `{$REGION}` (`TSpecType`)

Original (correct, from `.BCK1`):

```pascal
TSpecType = (
    {$REGION 'Documentation'}
    /// <summary>
    /// Not used yet
    /// </summary>
    {$ENDREGION}
    SpecType_Undefined = 0,
    {$REGION 'Documentation'}
    /// <summary>
    /// USL/LSL
    /// </summary>
    {$ENDREGION}
    SpecType_Double = 1, // Bilateral
    ...
);
```

After `yadf --b` (broken):

```pascal
TSpecType = (
    {$REGION 'Documentation'} /// <summary> /// Not used yet /// </summary> {$ENDREGION} SpecType_Undefined = 0,
    {$REGION 'Documentation'} /// <summary> /// USL/LSL /// </summary> {$ENDREGION} SpecType_Double = 1, // Bilateral
    ...
);
```

Each member line now starts with `{$REGION 'Documentation'} /// <summary> ...`. The `///` runs to EOL, so `{$ENDREGION} SpecType_Undefined = 0,` is **inside the XMLDoc comment**. The enum loses every member. (Also note `///` is XMLDoc — YADF must treat `///` exactly like `//` for the EOL-comment barrier.)

Evidence 3 (`TFtrType`) is identical in shape: `TFtrType = (// Empty0 = 0, //FtrType_Dimension = 1, ... );` all on one line — whole enum commented out.

## Resulting compiler errors (Delphi 13 / RAD Studio 37, Win64)

```
MSCTYPES.PAS(185): error E2029: Identifier expected but ')' found
MSCTYPES.PAS(425): error E2029: Expression expected but 'RECORD' found
MSCTYPES.PAS(426): error E2029: '(' expected but identifier 'public' found
MSCTYPES.PAS(427): error E2029: 'TO' expected but 'CLASS' found
MSCTYPES.PAS(433): error E2029: Declaration expected but identifier 'TCharMClass' found
MSCTYPES.PAS(449): error E2003: Undeclared identifier: 'TCharMClass'
MSCTYPES.PAS(449): error E2070: Unknown directive: 'static'
... ~70 more, cascading through every dependent record helper ...
MSCTYPES.PAS(647): error E2100: Data type too large: exceeds 2 GB
MSCTYPES.PAS(665): error E2226: Compilation terminated; too many errors
```

The `record helper for` errors (425+) are the same mechanism: an interleaved `///`/`//` line was merged into the `Name = record helper for T` header, commenting out `record helper for T`.

## Root cause / fix

The line-merger (and the bracket-context reflow path that `BUG_COMMENT_MERGE.md` describes) must treat **`//` and `///`** as a hard line-merge barrier:

1. **Never append any token onto a line whose pending tail is a `//`/`///` comment** (the comment must remain the last thing on its physical line).
2. **Never merge a line up into a predecessor if the predecessor's tail is a `//`/`///` comment.**
3. Apply this in **every** reflow path: statement merger, the bracketed argument/array path (`BUG_COMMENT_MERGE`), **and the type-section / enum-list / `record helper` header path** (this bug). The existing `HasLineCommentOrOpenBlock` guard is clearly not consulted in the enum/type path.
4. The comment scan must be **string/char-literal aware** (ignore `//` inside `'...'`) and must treat `///` as `//`.
5. Also treat `{$REGION ...}` / `{$ENDREGION}` and other `{$...}` compiler directives as merge barriers when adjacent to comments/declarations — collapsing them around enum members (Evidence 2) is undesirable even independent of the comment bug.

### Suggested regression tests

- `T = (// hi`⏎`A = 0,`⏎`B = 1`⏎`);` → must NOT become `T = (// hi A = 0, B = 1 );`
- Enum with `///` XMLDoc + `{$REGION}` between members (copy `TSpecType` from `MSCTYPES.PAS.BCK1`) → members must remain on their own lines.
- `T = record helper for U` preceded by a `///` line → header must stay intact.
- Multi-line `Format(..., [a, // note`⏎`b])` (the `BUG_COMMENT_MERGE` case) → `b])` must not land on the `// note` line.

## Repro material (kept for you)

- Broken output: `C:\Projects\DB\ORM3\COMMON\MSCTYPES.PAS` (as written by YADF this run).
- Correct original: `C:\Projects\DB\ORM3\COMMON\MSCTYPES.PAS.BCK1` (YADF's own `--b` backup).
- `diff MSCTYPES.PAS.BCK1 MSCTYPES.PAS` shows the full corruption. **Do not lose these** — once Micronite reverts MSCTYPES from `.BCK1` to keep building, only your copy of the diff remains. Recommend copying both into the YADF repo test corpus now.

## Impact note

`yadf <project>.dproj --b` reported "503 ok, 0 failed" — YADF believes it succeeded. It produces no diagnostic for self-inflicted code destruction. Consider an optional `--verify` that round-trips each formatted file through the parser (or at least re-lexes and asserts comment/enum structure invariants) and refuses to overwrite on regression.
