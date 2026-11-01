unit polarity_collapse;

// CollapseShortBlocks polarity fixture (test_option_polarity.ps1). Spec:
// docs\help-site\options\collapse-short-blocks.md. CbA/CbB = short expanded
// block with begin on the header line; CbE/CbF = the same with begin on its
// own line; CbC/CbD = short one-line block; LongNameNumber* = a block whose
// folded form would exceed MaxLen (180).

interface

procedure RunCollapse(C: Boolean);

implementation

procedure RunCollapse(C: Boolean);
var
  CbA: Integer;
  CbB: Integer;
  CbC: Integer;
  CbD: Integer;
  CbE: Integer;
  CbF: Integer;
  LongNameNumberOne: Integer;
  LongNameNumberTwo: Integer;
  LongNameNumberThree: Integer;
begin
  CbC:= 3;
  LongNameNumberOne:= 1;
  LongNameNumberTwo:= 2;
  LongNameNumberThree:= 3;
  if C then begin
    CbA:= 1;
    CbB:= 2;
  end;
  if not C then
  begin
    CbE:= 1;
    CbF:= 2;
  end;
  while CbC > 0 do begin Dec(CbC); CbD:= CbC; end;
  if C then begin
    LongNameNumberOne:= LongNameNumberTwo + LongNameNumberThree + 1000;
    LongNameNumberTwo:= LongNameNumberOne + LongNameNumberThree + 2000;
    LongNameNumberThree:= LongNameNumberOne + LongNameNumberTwo + 3000;
  end;
  if CbA + CbB + CbD + CbE + CbF + LongNameNumberThree > 0 then
    CbC:= 0;
end;

end.
