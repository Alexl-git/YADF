---
id: break-if-body
title: Break if/then/else body onto its own line
summary: On: the then/else bodies of an if go on their own indented lines. Off: the whole if ("if C then A else B;") goes on one line when it fits the max length, else every body on its own line.
group: short-bodies
order: 10
default: "true"
ini: BreakIfBody
cli: --break-if
since: "1.0.0.0"
status: "stable"
---

# Break if/then/else body onto its own line

Two-way (since 1.0.21.0). On (default): every simple then/else body goes on its own indented line ("if X then A else B;" -> "if X then" / "  A" / "else" / "  B;"); "else if" chains stay glued. Off: the WHOLE if statement goes on one line when every body is one simple statement and the line fits the max length; otherwise every body goes on its own line -- an if/else is either one line or the fully broken form, never half-joined. Unchecked means the opposite layout, not "leave as written".

Never touched: a begin..end body (see Fold short begin..end onto one line), a body that is itself a control statement (if/for/while/with/case/repeat/try), a line holding a // comment. A body is never pulled onto a header that spans several lines. A { } comment right after then stays on the then line either way. The case else part (`else X;` inside a case statement) belongs to [One-statement case arm on its label line](case-arm-on-label-line.md), not to this option. Applies with Reflow lines on or off.

## With Pack short bodies

This rule is independent: it works on its own, whether or not [Pack short bodies onto their header line](pack-short-bodies.md) is used. Pack is only a preset -- checking it sets this rule to off (body joined onto the if line when it fits). If you then choose the other value for this rule yourself, your choice is respected (the Options page lists it under "Respected over Pack") and Pack does not override it.

## Example

Real YADF output for the "BreakIfBody" block of the preview sample (Demo\Sample.pas), all other options at their defaults:

```pascal
// input
procedure ShowBreakIfBody(var K: Integer);
begin
  if K > 0 then Inc(K) else Dec(K);
end;

// BreakIfBody = true (default)
procedure ShowBreakIfBody(var K: Integer);
begin
  if K > 0 then
    Inc(K)
  else
    Dec(K);
end;

// BreakIfBody = false
procedure ShowBreakIfBody(var K: Integer);
begin
  if K > 0 then Inc(K) else Dec(K);
end;
```

## Related

- [Break loop body onto its own line](break-loop-body.md) - the same two-way rule for for/while loops.
- [Break with body onto its own line](break-with-body.md) - the same two-way rule for with statements.
- [One-statement case arm on its label line](case-arm-on-label-line.md) - owns case arms and the case else part.
