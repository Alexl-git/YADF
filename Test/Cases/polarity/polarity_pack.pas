unit polarity_pack;

// PackShortBodies polarity fixture (test_option_polarity.ps1). Spec:
// docs\help-site\options\pack-short-bodies.md. Broken bodies use PkA..PkC,
// one-line bodies use PkD..PkF.

interface

procedure RunPack(N: Integer);

implementation

procedure RunPack(N: Integer);
var
  I: Integer;
  PkA: Integer;
  PkB: Integer;
  PkC: Integer;
  PkD: Integer;
  PkE: Integer;
  PkF: Integer;
begin
  PkA:= 0;
  PkB:= 0;
  PkC:= 0;
  PkD:= 0;
  PkE:= 0;
  PkF:= 0;
  for I:= 0 to N do
    Inc(PkA);
  if PkA > 0 then
    Dec(PkB);
  case N of
    0:
      Inc(PkC);
    1: Inc(PkF);
  end;
  for I:= 0 to N do Inc(PkD);
  if PkD > 0 then Dec(PkE);
end;

end.
