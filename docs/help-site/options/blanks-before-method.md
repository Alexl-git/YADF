---
id: blanks-before-method
title: Blanks before method
summary: Blank lines forced before each method body.
group: blank-lines
order: 30
default: "0"
ini: BlanksBeforeMethod
cli: --blanks-before-method
since: "1.0.0.0"
status: "stable"
---

# Blanks before method

Minimum blank lines before each top-level procedure / function /
constructor / destructor declaration.

## Example

Real YADF output for the "BlanksBeforeMethod" block of the preview sample (Demo\Sample.pas), all other options at their defaults:

```pascal
// input
procedure ShowBlanksBeforeMethod(var K: Integer);
begin
  Inc(K);
end;

// BlanksBeforeMethod = 0 (default)
procedure ShowBlanksBeforeMethod(var K: Integer);
begin
  Inc(K);
end;

// BlanksBeforeMethod = 1
procedure ShowBlanksBeforeMethod(var K: Integer);
begin
  Inc(K);
end;
```

## Related

- [Reflow lines (join and wrap)](reflow-lines.md) - Reflow lines that exceed MaxLen. When false, long lines are left as-is.
- [Trim trailing spaces](trim-trailing.md) - Trim trailing whitespace from every output line.
- [Max blank lines](max-blank-lines.md) - Maximum consecutive blank lines kept in output. Excess blanks are collapsed.
