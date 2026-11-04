---
id: tab-width
title: Tab width
summary: Width assumed for an existing tab on input, 1 to 16. YADF always emits spaces.
group: line-layout
order: 30
default: "4"
ini: TabWidth
cli: --tab-width
since: "1.0.0.0"
status: "stable"
---

# Tab width

How many spaces a leading TAB character expands to when YADF
normalizes leading whitespace. Tabs inside strings and comments
are preserved verbatim.

## Example

Real YADF output for the "TabWidth" block of the preview sample (Demo\Sample.pas), all other options at their defaults:

```pascal
// input
procedure ShowTabWidth(var K: Integer);
begin
	//. pinned comment, indented with one tab
  Inc(K);
end;

// TabWidth = 4 (default)
procedure ShowTabWidth(var K: Integer);
begin
    //. pinned comment, indented with one tab
  Inc(K);
end;

// TabWidth = 8
procedure ShowTabWidth(var K: Integer);
begin
        //. pinned comment, indented with one tab
  Inc(K);
end;
```

## Related

- [Max line length](max-len.md) - Maximum line length in columns. Long lines are reflowed when ReflowLines is true.
- [Indent step](indent.md) - Indentation step in spaces (each nesting level adds this many).
