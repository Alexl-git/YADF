---
id: uses-comma-last
title: Put the separator last in broken lists
summary: Separator side in a broken uses clause or parameter list: off = separator first (", Unit", diff-friendly), on = separator last ("Unit,").
group: uses-clauses
order: 20
default: "false"
ini: UsesCommaLast
since: "1.0.0.0"
status: "stable"
---

# Put the separator last in broken lists

Style of the BROKEN (multi-line) uses clause. Only affects the
broken form; the inline single-line form is unchanged.
  false (default) -- comma-FIRST     true -- comma-LAST
    uses                               uses
      System.SysUtils                    System.SysUtils,
      , System.Classes                   System.Classes;
      ;
Comma-first (default) keeps diffs clean when units are added or
removed (each line is a complete row including its comma).

The same choice applies to a parameter list broken by
[Break parameters one per line](break-params-one-per-line.md):
"; B: Integer" leading (off) or "const A: string;" ending each line (on).

This option does NOT govern the comma-first lists produced by [Break long expressions](break-long-expressions.md) (long bracketed lists such as array constants). Those are always comma-first, so one file can legitimately contain both comma styles.

## Example

Real YADF output for the "UsesAlwaysBreak + UsesCommaLast" block of the preview sample (Demo\Sample.pas), all other options at their defaults:

```pascal
// input
uses System.SysUtils, System.Types, System.Math;

// UsesCommaLast = false (default)
uses
  System.SysUtils
  , System.Types
  , System.Math
  ;

// UsesCommaLast = true
uses
  System.SysUtils,
  System.Types,
  System.Math;
```

## Related

- [Break uses clauses, one unit per line](uses-always-break.md) - Always break uses clauses one unit per line.
