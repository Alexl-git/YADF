---
id: break-if-body
title: Break if/then/else body onto its own line
summary: On: the then/else bodies of an if go on their own indented lines. Off: the whole if ("if C then A else B;") goes on one line when it fits the max length, else every body on its own line.
group: reflow-whitespace
order: 110
default: "true"
ini: BreakIfBody
since: "1.0.0.0"
status: "stable"
---

# Break if/then/else body onto its own line

Two-way (since 1.0.21.0). On (default): every simple then/else body goes on its own indented line ("if X then A else B;" -> "if X then" / "  A" / "else" / "  B;"); "else if" chains stay glued. Off: the WHOLE if statement goes on one line when every body is one simple statement and the line fits the max length; otherwise every body goes on its own line -- an if/else is either one line or the fully broken form, never half-joined. Unchecked means the opposite layout, not "leave as written".

Never touched: a begin..end body (see Collapse short begin..end blocks), a body that is itself a control statement (if/for/while/with/case/repeat/try), a line holding a // comment. A body is never pulled onto a header that spans several lines. A { } comment right after then stays on the then line either way. The case else part (`else X;` inside a case statement) belongs to [Case arm on its label line](case-arm-on-label-line.md), not to this option. Applies with Reflow long lines on or off.

The retired option "Pack short bodies" is still read from an INI as an alias: PackShortBodies = true turns this option (and Break loop/with body) off, unless the same INI sets it to true explicitly.

## Example

```pascal
// input
if C then A:= 1 else A:= 2;
if C then
  B:= 1
else
  B:= 2;
if C then { why } Inc(A);

// on (default)
if C then
  A:= 1
else
  A:= 2;
if C then
  B:= 1
else
  B:= 2;
if C then { why }
  Inc(A);

// off
if C then A:= 1 else A:= 2;
if C then B:= 1 else B:= 2;
if C then { why } Inc(A);
```

## Related

- [Break if/then/else body onto its own line](break-if-body.md) - the same two-way rule for if statements.
- [Break loop body onto its own line](break-loop-body.md) - the same two-way rule for for/while loops.
- [Break with body onto its own line](break-with-body.md) - the same two-way rule for with statements.
- [Case arm on its label line](case-arm-on-label-line.md) - owns case arms and the case else part.
