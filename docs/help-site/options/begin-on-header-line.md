---
id: begin-on-header-line
title: Put begin on the same line as then / do / else
summary: On: begin joins the line of its then / do / else, case label or case else ("if C then begin", "end else begin", "9: begin"). Off: begin goes on its own line, and "end" / "else" / "begin" on three lines. A block that "Collapse short begin..end blocks" folds onto one line is not affected. Off by default.
group: reflow-whitespace
order: 80
default: "false"
ini: BeginOnHeaderLine
since: "1.0.21.0"
status: "stable"
---

# Put begin on the same line as then / do / else

Where the `begin` of a control block goes. Two-way: unchecked means the opposite layout, not "leave as written".

On: `begin` joins the line of the then / do / else, the case label or the case else that opens its block (`if C then begin`, `while X do begin`, `9: begin`, `else begin`), and an `end` / `else` / `begin` sequence becomes `end else begin` -- joined when the line fits the max line length.

Off (default): `begin` goes on its own line at the column of its header (`if C then` / `begin`), and `end else begin` is laid out as `end` / `else` / `begin` on three lines.

A `//` comment after then / do / else or the label keeps `begin` on its own line; a `//` comment after `begin` moves with it. A block that "Collapse short begin..end blocks" folds onto one line is not affected (the fold wins). Applies whether "Reflow long lines" is on or off.

## Example

```pascal
// input
if C then begin
  A:= 1;
end else begin
  A:= 2;
end;
while A > 0 do
begin
  Dec(A);
end;
case N of
  9: begin
    A:= 9;
  end;
end;

// off (default)
if C then
begin
  A:= 1;
end
else
begin
  A:= 2;
end;
while A > 0 do
begin
  Dec(A);
end;
case N of
  9:
  begin
    A:= 9;
  end;
end;

// on
if C then begin
  A:= 1;
end else begin
  A:= 2;
end;
while A > 0 do begin
  Dec(A);
end;
case N of
  9: begin
    A:= 9;
  end;
end;
```

## Related

- [Collapse short begin..end blocks](collapse-short-blocks.md) - Folds a short block onto one line; that layout wins over this option.
- [Case arm on its label line](case-arm-on-label-line.md) - Lays out one-statement arms; a begin..end arm follows this option.
- [Reflow long lines](reflow-lines.md) - This option applies whether reflow is on or off.