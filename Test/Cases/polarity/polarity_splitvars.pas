unit polarity_splitvars;

// SplitMultiVarDecls polarity fixture (test_option_polarity.ps1). Spec:
// docs\help-site\options\split-multi-var-decls.md. SvA, SvB = one grouped
// declaration; SvC / SvD = already one name per line. SvE, {note} SvF = a
// grouped declaration whose name list holds a comment.

interface

procedure RunSplitVars;
procedure RunSplitVarsNote;

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

procedure RunSplitVarsNote;
var
  SvE, {note} SvF: Integer;
begin
  SvE:= 1;
  SvF:= SvE;
  if SvF > 0 then
    SvE:= 0;
end;

end.
