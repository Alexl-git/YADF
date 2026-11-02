---
id: align-max-column
title: Align max column
summary: Maximum column an alignment may push to. Past this, alignment is skipped.
group: alignment
order: 60
default: "140"
ini: AlignMaxColumn
since: "1.0.0.0"
status: "stable"
---

# Align max column

Skip Pass-2 alignment for any anchor that would push a line past
this column (prevents one outlier from forcing huge padding on
every neighbor). Also caps the shared column used by
AlignMatchingShapes and by trailing-comment alignment. Wide
tables (e.g. long record-constant arrays) align out of the box at
the default below; very wide ones may still need it raised -- if
any anchor would cross this column the whole run is left
untouched. Raised from 100 to 140 (2026-05-17) so AlignMatchingShapes
aligns typical record-constant tables without a per-project bump.

## Example

Real YADF output for the "AlignMaxColumn" block of the preview sample (Demo\Sample.pas), all other options at their defaults:

```pascal
// input
procedure ShowAlignMaxColumn(var AParameterWithALongNameToPushTheColumnOut: TRect);
begin
  AParameterWithALongNameToPushTheColumnOut.Left:= 1; // x
  AParameterWithALongNameToPushTheColumnOut.Bottom:= 2; // y
end;

// AlignMaxColumn = 140 (default)
procedure ShowAlignMaxColumn(var AParameterWithALongNameToPushTheColumnOut: TRect);
begin
  AParameterWithALongNameToPushTheColumnOut.Left  := 1; // x
  AParameterWithALongNameToPushTheColumnOut.Bottom:= 2; // y
end;

// AlignMaxColumn = 50
procedure ShowAlignMaxColumn(var AParameterWithALongNameToPushTheColumnOut: TRect);
begin
  AParameterWithALongNameToPushTheColumnOut.Left:= 1; // x
  AParameterWithALongNameToPushTheColumnOut.Bottom:= 2; // y
end;
```

## Related

- [No space before :=](assign-no-space-before.md) - No space BEFORE := ("X:= 1" not "X := 1").
- [Space after :=](assign-space-after.md) - Single space AFTER := ("X:= 1" not "X:=1").
- [Align = in const blocks](align-const-equals.md) - Vertical-align = in const blocks.
