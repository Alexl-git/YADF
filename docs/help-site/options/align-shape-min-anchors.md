---
id: align-shape-min-anchors
title: Shape min anchors
summary: Minimum anchors required before shape-alignment kicks in.
group: alignment
order: 70
default: "3"
ini: AlignShapeMinAnchors
since: "1.0.0.0"
status: "stable"
---

# Shape min anchors

Floor on how many structural anchors a non-`:=` run's shared
skeleton must have before AlignMatchingShapes will align it. This
stops trivial 1-2 symbol shapes (e.g. every `Foo(x);` or `a.b;`)
from triggering noisy column padding across ordinary code. Lines
that already contain `:=` are unaffected by this floor, with one
exception: at 2 or less a closing `]` / `)` of the `:=` target is an
anchor too, so the brackets of same-shape assignments line up. A
closer after the `:=` is never padded.

## Indexed `:=` targets

```pascal
// AlignShapeMinAnchors = 3 (default): only := lines up
  A[1]  := 1;
  A[22] := 2;
  A[333]:= 3;

// AlignShapeMinAnchors = 2: the closing ] is anchor 1, := is anchor 2
  A[1  ]:= 1;
  A[22 ]:= 2;
  A[333]:= 3;
```

With "Align lines of the same shape" (AlignMatchingShapes) off, only
`:=` lines up at every value.

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

// AlignShapeMinAnchors = 3 (default)
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

// AlignShapeMinAnchors = 6
procedure ShowAlignMatchingShapes;
begin
  Writeln(Format('%d', [1  ]), 'a' , 22); // one
  Writeln(Format('%d', [333]), 'bb', 4 ); // two
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
