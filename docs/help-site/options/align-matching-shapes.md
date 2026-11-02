---
id: align-matching-shapes
title: Align lines of the same shape
summary: Align matching "shapes" (record-init lines, repeated field declarations).
group: alignment
order: 50
default: "true"
ini: AlignMatchingShapes
since: "1.0.0.0"
status: "stable"
---

# Align lines of the same shape

Generalises AlignSmartAssign beyond `:=` lines. When two or more
ADJACENT lines share an identical structural skeleton (same
sequence of operators/punctuation in the same order -- identifier
names, strings, and numbers are ignored), every shared anchor is
padded to a common column so the lines form a neat table. Applies
anywhere -- record-constant arrays, declarations, repeated calls
-- not just constant definitions. Lines whose skeletons differ
are never touched. A member `.` (`A.B`) is part of the skeleton
but is never padded. Set false to keep the old `:=`/const-only
behaviour.

## Example

Real YADF output for the "AlignMatchingShapes + AlignShapeMinAnchors" block of the preview sample (Demo\Sample.pas), all other options at their defaults:

```pascal
// input
procedure ShowAlignMatchingShapes;
begin
  Writeln(Format('%d', [1]), 'a', 22); // one
  Writeln(Format('%d', [333]), 'bb', 4); // two
end;

procedure ShowAlignShapeMinAnchors(var K: Integer);
begin
  Writeln(K, 'a', 22); // one
  Writeln(K, 'bbbbbb', 4); // two
end;

// AlignMatchingShapes = true (default)
procedure ShowAlignMatchingShapes;
begin
  Writeln(Format('%d', [1  ]), 'a' , 22); // one
  Writeln(Format('%d', [333]), 'bb', 4 ); // two
end;

procedure ShowAlignShapeMinAnchors(var K: Integer);
begin
  Writeln(K, 'a'     , 22); // one
  Writeln(K, 'bbbbbb', 4 ); // two
end;

// AlignMatchingShapes = false
procedure ShowAlignMatchingShapes;
begin
  Writeln(Format('%d', [1]), 'a', 22); // one
  Writeln(Format('%d', [333]), 'bb', 4); // two
end;

procedure ShowAlignShapeMinAnchors(var K: Integer);
begin
  Writeln(K, 'a', 22); // one
  Writeln(K, 'bbbbbb', 4); // two
end;
```

## Related

- [No space before :=](assign-no-space-before.md) - No space BEFORE := ("X:= 1" not "X := 1").
- [Space after :=](assign-space-after.md) - Single space AFTER := ("X:= 1" not "X:=1").
- [Align = in const blocks](align-const-equals.md) - Vertical-align = in const blocks.
