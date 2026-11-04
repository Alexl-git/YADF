---
id: uses-always-break
title: Break uses clauses, one unit per line
summary: Always break uses clauses one unit per line.
group: uses-clauses
order: 10
default: "true"
ini: UsesAlwaysBreak
cli: --uses-break
since: "1.0.0.0"
status: "stable"
---

# Break uses clauses, one unit per line

When true (default), every uses-style clause is rendered
one identifier per line, comma-first, with the closing
semicolon on its own line; the commas and the semicolon are indented one step,
at the column of the unit names:

    uses
      System.SysUtils
      , System.Classes
      ;

The separator side (comma-first or comma-last) is set by
[Put the separator last in broken lists](uses-comma-last.md).

When false, the clause stays on a single line if it fits in
MaxLen and contains no `in 'path'` items; otherwise it breaks
(and the closing semicolon still goes on its own line).

## Example

Real YADF output for the "UsesAlwaysBreak + UsesCommaLast" block of the preview sample (Demo\Sample.pas), all other options at their defaults:

```pascal
// input
uses System.SysUtils, System.Types, System.Math;

// UsesAlwaysBreak = true (default)
uses
  System.SysUtils
  , System.Types
  , System.Math
  ;

// UsesAlwaysBreak = false
uses System.SysUtils, System.Types, System.Math;
```

## Related

- [Put the separator last in broken lists](uses-comma-last.md) - Style of the broken (multi-line) uses clause. False (default) is comma-FIRST (leading comma, semicolon on its own line) -- the diff-friendly layout. True is comma-LAST (trailing comma per unit, semicolon on the last unit's line: "System.Classes;"). Only affects the multi-line form; the inline single-line form is unchanged.
