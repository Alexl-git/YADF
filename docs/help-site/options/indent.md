---
id: indent
title: Indent step
summary: Indentation step in spaces, 0 to 16 (each nesting level adds this many).
group: line-layout
order: 20
default: "2"
ini: Indent
cli: --indent
since: "1.0.0.0"
status: "stable"
---

id: indent
title: Indent step
summary: Indentation step in spaces, 0 to 16 (each nesting level adds this many).
group: line-layout
order: 20
default: "2"
ini: Indent
cli: --indent
since: "1.0.0.0"
status: "stable"
---

# Indent step

Number of spaces per indent level. Standard Delphi style is 2.

## Example

Real YADF output for the "Indent" block of the preview sample (Demo\Sample.pas), all other options at their defaults:

```pascal
// input
procedure ShowIndent(var K: Integer);
begin
  repeat
    Dec(K);
  until K <= 0;
end;

// Indent = 2 (default)
procedure ShowIndent(var K: Integer);
begin
  repeat
    Dec(K);
  until K <= 0;
end;

// Indent = 4
procedure ShowIndent(var K: Integer);
begin
    repeat
        Dec(K);
    until K <= 0;
end;
```

## Related

- [Max line length](max-len.md) - Maximum line length in columns. Long lines are reflowed when ReflowLines is true.
- [Tab width](tab-width.md) - Width assumed for an existing tab on input. YADF always emits spaces.
