unit polarity_splitvars;

// SplitMultiVarDecls polarity fixture (test_option_polarity.ps1). Spec:
// docs\help-site\options\split-multi-var-decls.md. SvA, SvB = one grouped
// declaration; SvC / SvD = already one name per line.

interface

procedure RunSplitVars;

implementation

procedure RunSplitVars;
var
  SvA, SvB: Integer;
  SvC: Integer;
  SvD: Integer;
begin
  SvA:= 1;
  SvB:= SvA;
  SvC:= SvB;
  SvD:= SvC;
  if SvD > 0 then
    SvA:= 0;
end;

end.
