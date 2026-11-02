---
id: break-loop-body
title: Break loop body onto its own line
summary: On: the body of a for/while loop goes on its own indented line. Off: a short simple body is joined onto the do line when it fits the max length.
group: bodies-and-blocks
order: 20
default: "true"
ini: BreakLoopBody
since: "1.0.0.0"
status: "stable"
---

# Break loop body onto its own line

Two-way (since 1.0.21.0). On (default): the body of a for/while loop goes on its own indented line. Off: a short simple body is joined onto the do line when the whole fits the max length. Unchecked means the opposite layout, not "leave as written".

Never touched: a begin..end body, a body that is itself a control statement, a line holding a // comment, and a header that spans several lines. Applies with Reflow lines on or off. The retired PackShortBodies = true (still read from an INI) turns this option off unless the same INI sets it to true.

## Example

Real YADF output for the "BreakLoopBody" block of the preview sample (Demo\Sample.pas), all other options at their defaults:

```pascal
// input
procedure ShowBreakLoopBody(var K: Integer);
begin
  while K > 0 do Dec(K);
end;

// BreakLoopBody = true (default)
procedure ShowBreakLoopBody(var K: Integer);
begin
  while K > 0 do
    Dec(K);
end;

// BreakLoopBody = false
procedure ShowBreakLoopBody(var K: Integer);
begin
  while K > 0 do Dec(K);
end;
```

## Related

- [Break if/then/else body onto its own line](break-if-body.md) - the same two-way rule for if statements.
- [Break with body onto its own line](break-with-body.md) - the same two-way rule for with statements.
- [One-statement case arm on its label line](case-arm-on-label-line.md) - owns case arms and the case else part.
