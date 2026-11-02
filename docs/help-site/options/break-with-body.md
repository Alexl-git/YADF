---
id: break-with-body
title: Break with body onto its own line
summary: On: the body of a with..do goes on its own indented line. Off: a short simple body is joined onto the do line when it fits the max length.
group: bodies-and-blocks
order: 30
default: "true"
ini: BreakWithBody
since: "1.0.0.0"
status: "stable"
---

# Break with body onto its own line

Two-way (since 1.0.21.0), same rules as [Break loop body onto its own line](break-loop-body.md) for "with ... do". On (default): the body goes on its own indented line. Off: a short simple body is joined onto the do line when the whole fits the max length. The retired PackShortBodies = true (still read from an INI) turns this option off unless the same INI sets it to true.

## Example

Real YADF output for the "BreakWithBody" block of the preview sample (Demo\Sample.pas), all other options at their defaults:

```pascal
// input
procedure ShowBreakWithBody(var R: TRect);
begin
  with R do Left:= 1;
end;

// BreakWithBody = true (default)
procedure ShowBreakWithBody(var R: TRect);
begin
  with R do
    Left:= 1;
end;

// BreakWithBody = false
procedure ShowBreakWithBody(var R: TRect);
begin
  with R do Left:= 1;
end;
```

## Related

- [Break if/then/else body onto its own line](break-if-body.md) - the same two-way rule for if statements.
- [Break loop body onto its own line](break-loop-body.md) - the same two-way rule for for/while loops.
- [One-statement case arm on its label line](case-arm-on-label-line.md) - owns case arms and the case else part.
