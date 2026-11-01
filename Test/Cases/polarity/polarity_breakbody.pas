unit polarity_breakbody;

// BreakIfBody / BreakLoopBody / BreakWithBody polarity fixture
// (test_option_polarity.ps1). Specs: docs\help-site\options\break-if-body.md,
// break-loop-body.md, break-with-body.md. One-line bodies: IfA, LpA, LpB, WtA;
// bodies already on their own line: IfB, LpC, LpD, WtB. LpE = one-line loop
// body with a trailing comment (spec: left alone).

interface

procedure RunBodies(C: Boolean);

implementation

type
  TBodyRec = record
    WtA: Integer;
    WtB: Integer;
  end;

procedure RunBodies(C: Boolean);
var
  I: Integer;
  IfA: Integer;
  IfB: Integer;
  LpA: Integer;
  LpB: Integer;
  LpC: Integer;
  LpD: Integer;
  LpE: Integer;
  R: TBodyRec;
begin
  LpA:= 5;
  LpB:= 0;
  LpC:= 5;
  LpD:= 0;
  LpE:= 5;
  if C then IfA:= 1 else IfA:= 2;
  if C then
    IfB:= 1
  else
    IfB:= 2;
  while LpA > 0 do Dec(LpA);
  for I:= 0 to 3 do Inc(LpB);
  while LpC > 0 do
    Dec(LpC);
  for I:= 0 to 3 do
    Inc(LpD);
  while LpE > 0 do Dec(LpE); // keep
  with R do WtA:= IfA;
  with R do
    WtB:= IfB;
  if R.WtA + R.WtB + LpB + LpD > 0 then
    LpA:= 0;
end;

end.
