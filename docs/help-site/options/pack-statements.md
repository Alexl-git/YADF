---
id: pack-statements
title: Pack several statements on one line
summary: On: adjacent plain statements ("A:= 1; B:= 2;") are packed onto one line while it fits the max length. Off: one statement per line. Block keywords (begin, repeat, try, case, record, class) always start a line either way. Off by default.
group: bodies-and-blocks
order: 60
default: "false"
ini: PackStatements
cli: --pack-statements
since: "1.0.21.0"
status: "stable"
---

# Pack several statements on one line

Several statements on one line. Two-way: unchecked means the opposite layout, not "leave as written".

On: adjacent plain statements -- assignments and calls written on consecutive lines at the same depth, with no block keyword, no label and no comment -- are packed onto one line while the line fits the max line length (`A:= 1;` / `B:= 2;` becomes `A:= 1; B:= 2;`).

Off (default): one statement per line (`A:= 1; B:= 2;` becomes two lines).

Fixed rule, whatever this option says: block keywords start a line and a block body never stays on its header line -- a routine `begin`, `repeat` / `until`, `try` / `finally` / `except`, `case ... of` and its arms, a record or class body and its visibility sections, and every `end`. Only "Fold short begin..end onto one line" may fold a short begin..end onto one line. Two declarations written on one line (`A: Integer; B: string;`) are always split one per line.

Left as written: a line holding a comment or a `{$...}` directive, an anonymous method, a procedural type, an anonymous record type in a declaration (`R: record X: Integer; end;`), an empty class or record (`TFoo = class end;`). Applies whether "Reflow lines" is on or off.

## Example

Real YADF output for the "PackStatements" block of the preview sample (Demo\Sample.pas), all other options at their defaults:

```pascal
// input
procedure ShowPackStatements(var K: Integer);
begin
  K:= 1; Inc(K);
end;

// PackStatements = false (default)
procedure ShowPackStatements(var K: Integer);
begin
  K:= 1;
  Inc(K);
end;

// PackStatements = true
procedure ShowPackStatements(var K: Integer);
begin
  K:= 1; Inc(K);
end;
```

## Related

- [Reflow lines (join and wrap)](reflow-lines.md) - Reflow lines that exceed the max line length. Off = long lines are left as-is.
- [Trim trailing spaces](trim-trailing.md) - Trim trailing whitespace from every output line.
- [Max blank lines](max-blank-lines.md) - Maximum consecutive blank lines kept in output. Excess blanks are collapsed.
