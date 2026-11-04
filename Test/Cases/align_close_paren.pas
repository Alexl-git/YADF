program align_close_paren;

// AlignMatchingShapes: a closing ) / ] is never padded (cosmetic, 2026-11-03):
// Writeln('one'   ); reads as a stray gap. Opening brackets, commas and the
// anchors after an interior closer still line up.
// Nor is space ever inserted between a callee and its ( : P(); next to
// Writeln('x'); was padded to P      ();.

var
  A: array[0..9] of Integer;
  X, Y: Integer;

procedure Foo(P, Q: Integer);
begin
end;

procedure P;
begin
end;

procedure Gamma(P, Q: Integer);
begin
end;

begin
  Writeln('one');
  Writeln('three');
  Writeln('a four');
  Foo(1, 2);
  Foo(10, 20);
  Foo(100, 200);
  A[1] := Abs(X);
  A[22] := Abs(Y + 1);
  A[333] := Abs(X * Y + 22);

  P();
  Writeln('x');

  Foo(1, 2);
  Gamma(3, 4);
end.