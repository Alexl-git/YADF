---
id: align-const-equals
title: Align = in const blocks
summary: Vertical-align = in const blocks.
group: alignment
order: 20
default: "true"
ini: AlignConstEquals
since: "1.0.0.0"
status: "stable"
---

# Align = in const blocks

Align `=` in adjacent `const NAME = VALUE;` lines.

## Example

Real YADF output for the "AlignConstEquals" block of the preview sample (Demo\Sample.pas), all other options at their defaults:

```pascal
// input
const
  CA = 1;
  CBbb = 22;

// AlignConstEquals = true (default)
const
  CA   = 1;
  CBbb = 22;

// AlignConstEquals = false
const
  CA = 1;
  CBbb = 22;
```

## Related

- [No space before :=](assign-no-space-before.md) - No space BEFORE := ("X:= 1" not "X := 1").
- [Space after :=](assign-space-after.md) - Single space AFTER := ("X:= 1" not "X:=1").
- [Align : in declarations](align-type-colon.md) - Vertical-align : in type / var / parameter blocks.
