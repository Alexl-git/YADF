---
id: break-loop-body
title: Break loop body onto its own line
summary: On: the body of a for/while loop goes on its own indented line. Off: a short simple body is joined onto the do line when it fits the max length.
group: short-bodies
order: 20
default: "true"
ini: BreakLoopBody
cli: --break-loop
since: "1.0.0.0"
status: "stable"
---

# Break loop body onto its own line

Two-way (since 1.0.21.0). On (default): the body of a for/while loop goes on its own indented line. Off: a short simple body is joined onto the do line when the whole fits the max length. Unchecked means the opposite layout, not "leave as written".

Never touched: a begin..end body, a body that is itself a control statement, a line holding a // comment, and a header that spans several lines. Applies with Reflow lines on or off.

## With Pack short bodies

This rule is independent: it works on its own, whether or not [Pack short bodies onto their header line](pack-short-bodies.md) is used. Pack is only a preset -- checking it sets this rule to off (body joined onto the loop header when it fits). If you then choose the other value for this rule yourself, your choice is respected (the Options page lists it under "Respected over Pack") and Pack does not override it.

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
