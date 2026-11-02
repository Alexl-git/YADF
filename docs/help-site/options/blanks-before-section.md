---
id: blanks-before-section
title: Blanks before section
summary: Blank lines forced before each interface section. 0 = no change.
group: blank-lines
order: 20
default: "0"
ini: BlanksBeforeSection
cli: --blanks-before-section
since: "1.0.0.0"
status: "stable"
---

# Blanks before section

Minimum blank lines before each `interface` / `implementation` /
`initialization` / `finalization` keyword.

## Example

Real YADF output for the "BlanksBeforeSection" block of the preview sample (Demo\Sample.pas), all other options at their defaults:

```pascal
// input
implementation

// BlanksBeforeSection = 0 (default)
implementation

// BlanksBeforeSection = 1
implementation
```

## Related

- [Reflow lines (join and wrap)](reflow-lines.md) - Reflow lines that exceed MaxLen. When false, long lines are left as-is.
- [Trim trailing spaces](trim-trailing.md) - Trim trailing whitespace from every output line.
- [Max blank lines](max-blank-lines.md) - Maximum consecutive blank lines kept in output. Excess blanks are collapsed.
