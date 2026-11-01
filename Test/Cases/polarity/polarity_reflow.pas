unit polarity_reflow;

// ReflowLines polarity fixture (test_option_polarity.ps1). Spec:
// docs\help-site\options\reflow-lines.md. Keys: Alpha = statement hand-broken
// mid-expression; Beta/Gamma = statements on separate lines (a statement
// boundary is structural); Delta = a line longer than MaxLen (180).

interface

procedure RunReflow;

implementation

function Sum3(A: Integer; B: Integer; C: Integer): Integer;
begin
  Result:= A + B + C;
end;

procedure RunReflow;
var
  Alpha: Integer;
  Beta: Integer;
  Gamma: Integer;
  Delta: Integer;
begin
  Alpha:= Sum3(1,
    2, 3);
  Beta:= Alpha;
  Gamma:= Beta;
  Delta:= Sum3(Alpha, Beta, Gamma) + Sum3(Gamma, Beta, Alpha) + Sum3(Beta, Alpha, Gamma) + Sum3(Alpha, Gamma, Beta) + Sum3(Gamma, Alpha, Beta) + Sum3(Beta, Gamma, Alpha) + Sum3(Alpha, Beta, Beta);
  if Delta > Gamma then
    Alpha:= Delta;
end;

end.
