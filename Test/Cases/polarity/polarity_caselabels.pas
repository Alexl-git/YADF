unit polarity_caselabels;

// BreakCaseLabels polarity fixture (test_option_polarity.ps1). Spec:
// docs\help-site\options\break-case-labels.md. CsA = a multi-label arm on one
// line; CsB = the same statement already written one label per line.

interface

procedure RunCaseLabels(N: Integer);

implementation

procedure RunCaseLabels(N: Integer);
var
  CsA: Integer;
  CsB: Integer;
begin
  CsA:= 0;
  CsB:= 0;
  case N of
    1, 2, 3: Inc(CsA);
    5: Inc(CsB);
    6: Inc(CsB);
  end;
  if CsA + CsB > 0 then
    CsA:= 0;
end;

end.
