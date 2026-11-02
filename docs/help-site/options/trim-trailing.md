---
id: trim-trailing
title: Trim trailing spaces
summary: Trim trailing whitespace from every output line.
group: spacing
order: 40
default: "true"
ini: TrimTrailing
cli: --trim-trailing
since: "1.0.0.0"
status: "stable"
---

# Trim trailing spaces

Strip trailing whitespace from every emitted line. Strongly
recommended on; turning it off is mostly for diff debugging.

## Example

Real YADF output for the "TrimTrailing" block of the preview sample (Demo\Sample.pas), all other options at their defaults:

```pascal
// input
procedure ShowTrimTrailing(var K: Integer);
begin
  // three blanks follow   
  Inc(K);
end;

// TrimTrailing = true (default)
procedure ShowTrimTrailing(var K: Integer);
begin
  // three blanks follow
  Inc(K);
end;

// TrimTrailing = false
procedure ShowTrimTrailing(var K: Integer);
begin
  // three blanks follow   
  Inc(K);
end;
```

## Related

- [Reflow lines (join and wrap)](reflow-lines.md) - Reflow lines that exceed MaxLen. When false, long lines are left as-is.
- [Max blank lines](max-blank-lines.md) - Maximum consecutive blank lines kept in output. Excess blanks are collapsed.
- [Blanks before section](blanks-before-section.md) - Blank lines forced before each interface section. 0 = no change.
