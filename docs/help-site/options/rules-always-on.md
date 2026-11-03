---
id: rules-always-on
title: Rules (always on)
summary: Layout rules YADF applies whatever the settings, the options whose "off" keeps the source as written, and the options that depend on each other.
group: rules
groupTitle: Rules (always on)
order: 10
default: ""
since: "1.0.21.0"
status: "stable"
manual: true
---

# Rules (always on)

YADF is an opinionated formatter: it treats the code as one long string and breaks it according to the settings and the rules below. An unchecked box gives the opposite layout, not "leave as written" -- except for the few options listed under "Off = kept as written". Everything that no option covers follows these rules. Each rule has a "Rule:" block in the preview sample (Demo\Sample.pas); the examples are real YADF output of those blocks.

## Block keywords start a line

`begin` of a routine, `repeat` / `until`, `try` / `finally` / `except`, `case .. of`, its arms and its `else`, a record or class body and its visibility sections, and every `end` start a line of their own, whatever [Pack several statements on one line](pack-statements.md) says. Only [Fold short begin..end onto one line](collapse-short-blocks.md) may fold a short begin..end. Kept whole: comment lines, compiler directives, asm blocks, anonymous routines and procedural types, an inline `R: record .. end` in a var declaration, an empty `class end`, and `public type`.

```pascal
// input
repeat Dec(K); until K <= 0; try Inc(K); finally Dec(K); end;

// output
repeat
  Dec(K);
until K <= 0;
try
  Inc(K);
finally
  Dec(K);
end;
```

## One declaration per line

Two declarations written on one line (`A: T; B: T;`) are always split. A combined declaration (`A, B: T`) is a different thing: it is split only by [Split "A, B: T" into one per name](split-multi-var-decls.md).

```pascal
// input
var
  RuleA: Integer; RuleB: Integer;

// output
var
  RuleA: Integer;
  RuleB: Integer;
```

## Tight parens and single spaces

No blank after `(` or `[` and none before `)` or `]`; a run of blanks inside code becomes one blank; no blank before a `:`, `;` or member `.` of code (so with all alignment options off a declaration is plain `Name: Type;`). Only alignment adds blanks back: a member `.` is an ordinary anchor of [Align lines of the same shape](align-matching-shapes.md), padded only when every line of the run has it (`Eta  .Th:= 3;` / `Omega.Th:= 4;`), never in a line that lacks it. Strings and comments are never touched.

```pascal
// input
Writeln( Format( '%d',   [1] ) );

// output
Writeln(Format('%d', [1]));
```

## Comments

- A `//` comment pins its line: it stays at the end of its line, and a `//` anywhere in a span -- the last line included -- blocks every join of that span (reflow, routine headers, if / loop / with bodies, case arms and labels, Collapse, Pack several statements). A join would put code after it or make it impossible to undo.
- A one-line `{...}` or `(*...*)` comment inside code travels with the token next to it (`if A {+ B} > C then` keeps the commented-out code where it was). When a line is split at the comment, it goes to the end of the earlier piece.
- Multi-line comments and compiler directives pin, like `//`.
- YADF never removes a comment, with one exception: the `// TODO -oYADF -cd10 :` flags that [Hoist inline vars (Delphi 10.2.3)](delphi10-compat.md) adds are YADF's own and are removed by a run with that option off. A TODO you wrote yourself (even `// TODO -oYADF : ...`) is never touched.

```pascal
// input
repeat {count down} Dec(K); until K <= 0;
Writeln(Format('%d %d', [K, // keeps the line break
  K]));

// output
repeat {count down}
  Dec(K);
until K <= 0;
Writeln(Format('%d %d', [K, // keeps the line break
  K]));
```

## Off = kept as written

These options are the exceptions to "unchecked = the opposite layout": turned off, they keep what the author wrote.

- [Reflow lines (join and wrap)](reflow-lines.md) -- the author's line breaks inside statements and long lines. Only what this option covers: every other construct still follows its own option.
- [Split "A, B: T" into one per name](split-multi-var-decls.md) -- combined declarations stay combined.
- [No space before :=](assign-no-space-before.md), [Space after :=](assign-space-after.md), [Space around operators](space-around-operators.md) -- the author's spacing.
- [Label the end of long blocks](label-long-blocks.md) -- no labels added, existing ones kept.
- The casing options ([Lowercase keywords](lowercase-keywords.md), [Uppercase hex](upper-hex-numbers.md), [Uppercase directives](upper-directives.md), [First-occurrence casing](first-occ-casing.md)) -- the author's casing.

## Options that depend on each other

- [Join routine headers split by hand](join-routine-headers.md) off implies [Break parameters one per line](break-params-one-per-line.md) on (the Options page checks and disables that box).
- The retired [Pack short bodies](pack-short-bodies.md) is read from an INI as an alias: `PackShortBodies = true` sets the three Break ... body options off (if, for / while and with bodies) and [One-statement case arm on its label line](case-arm-on-label-line.md) on. A Break ... body option set to true explicitly in the same INI wins for its own construct.
- [Put begin on the same line as then / do / else](begin-on-header-line.md) does not apply to a block that [Fold short begin..end onto one line](collapse-short-blocks.md) folds.
- [Long expressions: one part per line](break-long-expressions.md) works only while [Reflow lines](reflow-lines.md) is on.
- [Put the separator last in broken lists](uses-comma-last.md) also sets the separator side of a parameter list broken by [Break parameters one per line](break-params-one-per-line.md).
- [Align := runs (master switch for shapes)](align-smart-assign.md) off also stops [Align lines of the same shape](align-matching-shapes.md) and trailing-comment alignment.
- An if / for / while / with inside a case arm follows its Break ... body option exactly as elsewhere; [Break case labels one per line](break-case-labels.md) repeats the statement, which then follows [One-statement case arm on its label line](case-arm-on-label-line.md).