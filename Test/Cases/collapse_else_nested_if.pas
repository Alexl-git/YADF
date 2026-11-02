unit collapse_else_nested_if;

// CollapseShortBlocks ON + BreakIfBody OFF: a folded lse begin if B then X; end;
// must stay folded. BreakControlBodies read lse begin if B then as an
// lse if header and split the folded block on every second format.

interface

procedure Pick(A, B: Boolean);

implementation

procedure Pick(A, B: Boolean);
begin
  if A then
  begin
    if B then
      Writeln(1);
  end
  else
  begin
    if B then
      Writeln(2);
  end;
  if A then
    Writeln(3)
  else
  begin
    if B then
      Writeln(4);
  end;
end;

end.