---
id: collapse-short-blocks
title: Fold short begin..end onto one line
summary: Fold a short begin..end body of if/for/while/with, a case arm or the case else onto one line when it fits; off = expand such one-line blocks. Off by default.
group: bodies-and-blocks
order: 50
default: "false"
ini: CollapseShortBlocks
cli: --collapse-blocks
since: "1.0.0.0"
status: "stable"
---

id: collapse-short-blocks
title: Fold short begin..end onto one line
summary: Fold a short begin..end body of if/for/while/with, a case arm or the case else onto one line when it fits; off = expand such one-line blocks. Off by default.
group: bodies-and-blocks
order: 50
default: "false"
ini: CollapseShortBlocks
cli: --collapse-blocks
since: "1.0.0.0"
status: "stable"
---

# Fold short begin..end onto one line

Fold a short control-statement begin..end body onto one line when it fits MaxLen: an if/for/while/with/else header, a case arm label (`9: begin`) or the case else, whose block holds only simple one-statement-per-line code becomes "if X then begin A := 1; B := 2; end;" (since 1.0.21.0 case arms and the case else are folded and expanded like any other block). Only pure simple-statement bodies fold -- a nested block, a multi-line statement, or any comment leaves the block expanded; routine bodies are never folded. Off by default: OFF actively EXPANDS such blocks -- a control block written on one line (or half-broken) gets one statement per line and `end` on its own line, `begin` placed per "Put begin on the same line as then / do / else"; a block holding a comment, a {$...} directive, asm or a multi-line string is left as written.

This is the only exception to the fixed rule that block keywords start a line (see "Pack several statements on one line"): a routine body, repeat, try, case and record / class bodies are always expanded.

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

// CollapseShortBlocks = false (default)
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

// CollapseShortBlocks = true
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
  while K > 5 do begin Dec(K); end;
end;
```

## Related

- [Put begin on the same line as then / do / else](begin-on-header-line.md) - Places begin in a block this option leaves expanded.

- [Reflow lines (join and wrap)](reflow-lines.md) - Reflow lines that exceed MaxLen. When false, long lines are left as-is.
- [Trim trailing spaces](trim-trailing.md) - Trim trailing whitespace from every output line.
- [Max blank lines](max-blank-lines.md) - Maximum consecutive blank lines kept in output. Excess blanks are collapsed.
