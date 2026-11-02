---
id: assign-space-after
title: Space after :=
summary: Single space AFTER := ("X:= 1" not "X:=1"). Off = kept as written.
group: spacing
order: 20
default: "true"
ini: AssignSpaceAfter
since: "1.0.0.0"
status: "stable"
---

# Space after :=

On (default): exactly one space after `:=` (`X:=1` becomes `X:= 1`).

Off: kept as written -- YADF neither adds nor removes the space.

## Example

Real YADF output for the "AssignSpaceAfter" block of the preview sample (Demo\Sample.pas), all other options at their defaults:

```pascal
// input
procedure ShowAssignSpaceAfter(var K: Integer);
begin
  K:=1;
end;

// AssignSpaceAfter = true (default)
procedure ShowAssignSpaceAfter(var K: Integer);
begin
  K:= 1;
end;

// AssignSpaceAfter = false
procedure ShowAssignSpaceAfter(var K: Integer);
begin
  K:=1;
end;
```

## Related

- [No space before :=](assign-no-space-before.md) - No space BEFORE := ("X:= 1" not "X := 1").
- [Align = in const blocks](align-const-equals.md) - Vertical-align = in const blocks.
- [Align : in declarations](align-type-colon.md) - Vertical-align : in type / var / parameter blocks.
