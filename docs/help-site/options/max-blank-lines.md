---
id: max-blank-lines
title: Max blank lines
summary: Maximum consecutive blank lines kept in output. Excess blanks are collapsed.
group: blank-lines
order: 10
default: "1"
ini: MaxBlankLines
cli: --max-blank-lines
since: "1.0.0.0"
status: "stable"
---

# Max blank lines

Cap on consecutive blank lines anywhere in the output. The blank-
line floor options below (BlanksBeforeSection/Method/Type) win
over this cap when they ask for more blanks than this allows.

## Example

Real YADF output for the "MaxBlankLines" block of the preview sample (Demo\Sample.pas), all other options at their defaults:

```pascal
// input
procedure ShowMaxBlankLines(var K: Integer);
begin
  Inc(K);


  Dec(K);
end;

// MaxBlankLines = 1 (default)
procedure ShowMaxBlankLines(var K: Integer);
begin
  Inc(K);

  Dec(K);
end;

// MaxBlankLines = 2
procedure ShowMaxBlankLines(var K: Integer);
begin
  Inc(K);


  Dec(K);
end;
```

## Related

- [Reflow lines (join and wrap)](reflow-lines.md) - Reflow lines that exceed MaxLen. When false, long lines are left as-is.
- [Trim trailing spaces](trim-trailing.md) - Trim trailing whitespace from every output line.
- [Blanks before section](blanks-before-section.md) - Blank lines forced before each interface section. 0 = no change.
