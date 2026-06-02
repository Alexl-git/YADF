> **STATUS: RESOLVED (2026-05-15, YADF 1.0.1.16).** Line-merge / reflow now
> treats `//` and `///` as a hard merge barrier in all reflow paths, including
> the bracketed argument/array path. Regression test:
> `Test/Cases/bug_comment_merge_arglist.pas`. Kept for history / regression
> reference only. (Same fix covers `FIXED_LINE_MERGE_OVER_COMMENT.md`.)

# YADF BUG — line-reflow merges code onto a line ending in a `//` comment (silently comments out code)

**Reported by:** Claude Opus working the Micronite ORM3 project, 2026-05-15
**Severity:** HIGH — produces code that does not compile, and the cause is visually easy to miss (the lost code looks like part of a comment).
**Sibling precedent:** see `C:\Projects\YADF\BUG_LE_OPERATOR.md` (same era, different defect). This one is in the line-merge / reflow path, likely the same area as the `HasLineCommentOrOpenBlock` guard added in the YADF v1.0 session.

---

## Symptom

A multi-line call argument list that contains an **end-of-line `//` comment on one of the argument lines** gets reflowed such that the **next argument (on the following source line) is pulled up onto the comment line**. Everything after the `//` is now a comment, so that argument — and the closing `])` / `)` tokens — vanish into the comment. The result is an unbalanced, truncated expression and a cascade of parser errors.

## Minimal repro

Input (well-formed Delphi; the `//` is a normal trailing comment on one array element):

```pascal
CodeSite.Send(csmGreen, Format('  LABEL "%s" vis=%s layout=%s capAlign[H=%s V=%s] rect[%s]',
  [LI.CaptionOptions.Text,
   YN(LI.CaptionOptions.Visible),
   EN(TypeInfo(TdxCaptionLayout), Ord(LI.CaptionOptions.Layout)),
   EN(TypeInfo(TAlignment), Ord(LI.CaptionOptions.AlignHorz)),
   'ord' + IntToStr(Ord(LI.CaptionOptions.AlignVert)), // type not in scope; ord only
   RS(LI.ViewInfo.CaptionViewInfo.Bounds)]));
```

Output after the YADF pass (reconstructed exactly from the broken file):

```pascal
CodeSite.Send(csmGreen, Format('  LABEL "%s" vis=%s layout=%s capAlign[H=%s V=%s] rect[%s]', [LI.CaptionOptions.Text, YN(LI.CaptionOptions.Visible),
      EN(TypeInfo(TdxCaptionLayout), Ord(LI.CaptionOptions.Layout)), EN(TypeInfo(TAlignment), Ord(LI.CaptionOptions.AlignHorz)), 'ord'
    + IntToStr(Ord(LI.CaptionOptions.AlignVert)), // type not in scope; ord only RS(LI.ViewInfo.CaptionViewInfo.Bounds)])
    );
```

Look at the third line. The next array element **`RS(LI.ViewInfo.CaptionViewInfo.Bounds)])`** has been appended to the line that already ended with **`// type not in scope; ord only`**. It is now inside the comment. The Format array therefore loses its final element and its `]` `)` `)` closers; the orphaned `);` on the next line has nothing to close.

## Resulting compiler errors (Delphi 13 / RAD Studio 37)

```
Blueprint4.pas: error E2029: Expression expected but ')' found
Blueprint4.pas: error E2029: ')' expected but 'IF' found
Blueprint4.pas: error E2029: Expression expected but 'BEGIN' found
Blueprint4.pas: error E2250: There is no overloaded version of 'Send' that can be called with these arguments
Blueprint4.pas: error E2029: 'END' expected but 'ELSE' found
Blueprint4.pas: error E2029: Declaration expected but identifier '<next ident>' found
Blueprint4.pas: error F2063: Could not compile used unit '...'
```

The errors point *near* the damage but the real cause (a swallowed argument) is one line up and easy to misread as intentional commentary.

## Root cause hypothesis

YADF's line-join / reflow logic decided this argument list was short enough to re-wrap and, while merging continuation lines, **appended the following source line to a target line whose trailing run is a `//` line comment**. A `//` comment extends to physical end-of-line, so any token placed after it on the same physical line is consumed by the comment.

The existing guard from the YADF v1.0 session — `HasLineCommentOrOpenBlock` ("blocks merging onto any line with a `//` or unclosed `{`/`(*`") — is the right idea but is **not firing for this case**. Likely gaps:

1. The guard may check the *source* line being moved, not the *destination* line. Here the destination line ends in `//…`; appending onto it is what corrupts. The check must reject **target lines whose effective tail is a `//` comment** (i.e. there is a `//` not closed by end-of-statement before the merge point).
2. The reflow may be happening inside a **bracketed argument/array context** (`[ … ]` / `( … )`) where a different code path does the re-wrapping and bypasses `HasLineCommentOrOpenBlock` entirely.
3. String-literal awareness: ensure the `//` scan ignores `//` occurring **inside a string literal** (e.g. `'http://x'`) so the fix doesn't over-block; but a real trailing comment must hard-block the merge.

## Suggested fix

- Before merging line *N+1* up onto line *N* (or merging *N* with neighbors), scan line *N* with a string/char-literal-aware tokenizer. If a `//` token exists outside any string/char literal and is not on its own already-isolated comment line that will be preserved, **forbid the merge** (keep the line break, or move the comment to its own line above/below and then merge).
- Apply this guard uniformly in **all** reflow paths, including the bracketed argument-list / array-literal wrapper path — not only the statement-level merger.
- Add a regression test: a multi-line `Format(... , [a, b, c, // note` newline `d])` array where one element line ends in `//`. Assert the formatter never places `d])` on the `// note` line. (A companion to the `<=` regression test from `BUG_LE_OPERATOR.md`.)

## Workaround applied on the Micronite side (so you can reproduce against a known-good target)

The offending construct was rewritten to avoid an **in-expression trailing `//` comment**: the explanatory comment was moved to its **own line above** the statement, and the value was made a plain `%d` arg. This compiles and is formatter-stable:

```pascal
// capAlignV printed as ordinal (its enum type is not in this unit's scope): 0=tavTop 1=tavCenter 2=tavBottom
CodeSite.Send(csmGreen, Format('  LABEL "%s" vis=%s layout=%s capAlign[H=%s V=ord%d] rect[%s]',
  [LI.CaptionOptions.Text,
   YN(LI.CaptionOptions.Visible),
   EN(TypeInfo(TdxCaptionLayout), Ord(LI.CaptionOptions.Layout)),
   EN(TypeInfo(TAlignment), Ord(LI.CaptionOptions.AlignHorz)),
   Ord(LI.CaptionOptions.AlignVert),
   RS(LI.ViewInfo.CaptionViewInfo.Bounds)]));
```

This is only a workaround — YADF must not silently destroy code when a developer legitimately puts a trailing `//` comment on one element of a multi-line argument/array list.

## File for repro

`C:\Projects\DB\ORM3\CLIENT\Blueprint4.pas`, procedure `TfrmBlueprint4.DumpLayoutGeometry` (the `LABEL` `CodeSite.Send`). A pre-edit backup of the whole unit from this session is at `C:\Projects\DB\ORM3\CLIENT\Blueprint4.pas.BCK_CPYOP` if you want the original-vs-mangled diff.
