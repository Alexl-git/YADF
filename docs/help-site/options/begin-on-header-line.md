---
id: begin-on-header-line
title: Put begin on the same line as then / do / else
summary: On: begin joins the line of its then / do / else, case label or case else ("if C then begin", "end else begin", "9: begin"). Off: begin goes on its own line, and "end" / "else" / "begin" on three lines. A block that "Fold short begin..end onto one line" folds onto one line is not affected. Off by default.
group: bodies-and-blocks
order: 10
default: "false"
ini: BeginOnHeaderLine
cli: --begin-on-header
since: "1.0.21.0"
status: "stable"
---

# Put begin on the same line as then / do / else

Where the `begin` of a control block goes. Two-way: unchecked means the opposite layout, not "leave as written".

On: `begin` joins the line of the then / do / else, the case label or the case else that opens its block (`if C then begin`, `while X do begin`, `9: begin`, `else begin`), and an `end` / `else` / `begin` sequence becomes `end else begin` -- joined when the line fits the max line length.

Off (default): `begin` goes on its own line at the column of its header (`if C then` / `begin`), and `end else begin` is laid out as `end` / `else` / `begin` on three lines.

A `//` comment after then / do / else or the label keeps `begin` on its own line; a `//` comment after `begin` moves with it. A block that "Fold short begin..end onto one line" folds onto one line is not affected (the fold wins). Applies whether "Reflow lines" is on or off.

## Example

Real YADF output for the "BeginOnHeaderLine + CollapseShortBlocks" block of the preview sample (Demo\Sample.pas), all other options at their defaults:

```pascal
// input
procedure ShowBeginOnHeaderLine(var K: Integer);
begin
  if K > 0 then begin
    Inc(K); // up
    Inc(K);
  end else begin
    Dec(K); // down
    Dec(K);
  end;
end;

procedure ShowCollapseShortBlocks(var K: Integer);
begin
  while K > 5 do
  begin
    Dec(K);
  end;
end;

// BeginOnHeaderLine = false (default)
procedure ShowBeginOnHeaderLine(var K: Integer);
begin
  if K > 0 then
  begin
    Inc(K); // up
    Inc(K);
  end
  else
  begin
    Dec(K); // down
    Dec(K);
  end;
end;

procedure ShowCollapseShortBlocks(var K: Integer);
begin
  while K > 5 do
  begin
    Dec(K);
  end;
end;

// BeginOnHeaderLine = true
procedure ShowBeginOnHeaderLine(var K: Integer);
begin
  if K > 0 then begin
    Inc(K); // up
    Inc(K);
  end else begin
    Dec(K); // down
    Dec(K);
  end;
end;

procedure ShowCollapseShortBlocks(var K: Integer);
begin
  while K > 5 do begin
    Dec(K);
  end;
end;
```

## Related

- [Fold short begin..end onto one line](collapse-short-blocks.md) - Folds a short block onto one line; that layout wins over this option.
- [One-statement case arm on its label line](case-arm-on-label-line.md) - Lays out one-statement arms; a begin..end arm follows this option.
- [Reflow lines (join and wrap)](reflow-lines.md) - This option applies whether reflow is on or off.