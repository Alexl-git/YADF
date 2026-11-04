---
id: max-len
title: Max line length
summary: Maximum line length in columns (40 or more). Long lines are wrapped when "Reflow lines" is on.
group: line-layout
order: 10
default: "180"
ini: MaxLen
cli: --max-len
since: "1.0.0.0"
status: "stable"
---

# Max line length

Sets the column at which YADF starts wrapping a line. A line longer than this
value is broken at the safest available point (after a comma, before an
operator) when [Reflow lines (join and wrap)](reflow-lines.md) is on.

## When it does not apply

Lines that contain a string literal or a `//` line comment may run past the
limit. Breaking inside a literal would change what the program does, so YADF
leaves those lines alone by design.

## Example

Real YADF output for the "MaxLen" block of the preview sample (Demo\Sample.pas), all other options at their defaults:

```pascal
// input
procedure ShowMaxLen(const S: string);
begin
  Writeln(Format('%s has %d characters, %d of them before the first "a", %d before the first "b" and %d before "c"', [S, Length(S), Pos('a', S), Pos('b', S), Pos('c', S)]));
end;

// MaxLen = 180 (default)
procedure ShowMaxLen(const S: string);
begin
  Writeln(Format('%s has %d characters, %d of them before the first "a", %d before the first "b" and %d before "c"', [S, Length(S), Pos('a', S), Pos('b', S), Pos('c', S)]));
end;

// MaxLen = 150
procedure ShowMaxLen(const S: string);
begin
  Writeln(Format(
    '%s has %d characters, %d of them before the first "a", %d before the first "b" and %d before "c"'
  , [S, Length(S), Pos('a', S), Pos('b', S), Pos('c', S)]
  ));
end;
```

## Related

- [Reflow lines (join and wrap)](reflow-lines.md) - switches wrapping on or off.
- [Indent step](indent.md) - width of the continuation indent.
