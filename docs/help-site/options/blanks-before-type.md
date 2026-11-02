---
id: blanks-before-type
title: Blanks before type
summary: Blank lines forced before each top-level type declaration.
group: blank-lines
order: 40
default: "0"
ini: BlanksBeforeType
cli: --blanks-before-type
since: "1.0.0.0"
status: "stable"
---

# Blanks before type

Minimum blank lines before each `type` keyword.

## Example

Real YADF output for the "BlanksBeforeType" block of the preview sample (Demo\Sample.pas), all other options at their defaults:

```pascal
// input
type
  TSampleKind = (skNone, skLow, skHigh);

// BlanksBeforeType = 0 (default)
type
  TSampleKind = (skNone, skLow, skHigh);

// BlanksBeforeType = 1
type
  TSampleKind = (skNone, skLow, skHigh);
```

## Related

- [Reflow lines (join and wrap)](reflow-lines.md) - Reflow lines that exceed MaxLen. When false, long lines are left as-is.
- [Trim trailing spaces](trim-trailing.md) - Trim trailing whitespace from every output line.
- [Max blank lines](max-blank-lines.md) - Maximum consecutive blank lines kept in output. Excess blanks are collapsed.
