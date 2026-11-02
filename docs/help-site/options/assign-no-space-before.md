---
id: assign-no-space-before
title: No space before :=
summary: No space BEFORE := ("X:= 1" not "X := 1"). Off = kept as written.
group: spacing
order: 10
default: "true"
ini: AssignNoSpaceBefore
since: "1.0.0.0"
status: "stable"
---

# No space before :=

On (default): no space before `:=` (`X := 1` becomes `X:= 1`).

Off: kept as written -- YADF neither removes nor adds the space, so `X := 1` and `X:= 1` both stay as they are.

## Example

Real YADF output for the "AssignNoSpaceBefore" block of the preview sample (Demo\Sample.pas), all other options at their defaults:

```pascal
// input
procedure ShowAssignNoSpaceBefore(var K: Integer);
begin
  K := 1;
end;

// AssignNoSpaceBefore = true (default)
procedure ShowAssignNoSpaceBefore(var K: Integer);
begin
  K:= 1;
end;

// AssignNoSpaceBefore = false
procedure ShowAssignNoSpaceBefore(var K: Integer);
begin
  K := 1;
end;
```

## Related

- [Space after :=](assign-space-after.md) - Single space AFTER := ("X:= 1" not "X:=1").
- [Align = in const blocks](align-const-equals.md) - Vertical-align = in const blocks.
- [Align : in declarations](align-type-colon.md) - Vertical-align : in type / var / parameter blocks.
