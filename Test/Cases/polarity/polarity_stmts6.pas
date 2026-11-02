unit polarity_stmts6;

// PackStatements vs control bodies (task 6): a body line never packs with the
// statement after it.

interface

procedure RunStmts6(C: Boolean);

implementation

procedure RunStmts6(C: Boolean);
var
  PsA: Integer;
  PsB: Integer;
  PsC: Integer;
begin
  PsA := 0;
  PsB := 0;
  if C then
    PsA := 1;
  PsB := 2;
  PsC := 3;
  for PsA := 0 to 3 do
    PsB := PsA;
  PsC := 4;
  Writeln(PsA, PsB, PsC);
end;

end.