unit polarity_breakexpr;

// BreakLongExpressions polarity fixture (test_option_polarity.ps1). Spec:
// docs\help-site\options\break-long-expressions.md. ExprOneLine = a condition
// longer than MaxLen (180) on one line (V terms); ExprPerLine = the same shape
// already broken one component per line (W terms, also > 180 when joined).

interface

function ExprOneLine(const V: array of Integer): Boolean;
function ExprPerLine(const W: array of Integer): Boolean;

implementation

function ExprOneLine(const V: array of Integer): Boolean;
begin
  Result:= False;
  if (V[0] > 100) and (V[1] > 200) and (V[2] > 300) and (V[3] > 400) and (V[4] > 500) and (V[5] > 600) and (V[6] > 700) and (V[7] > 800) and (V[8] > 900) and (V[9] > 1000) and (V[10] > 1100) then
    Result:= True;
end;

function ExprPerLine(const W: array of Integer): Boolean;
begin
  Result:= False;
  if (W[0] > 100)
  and (W[1] > 200)
  and (W[2] > 300)
  and (W[3] > 400)
  and (W[4] > 500)
  and (W[5] > 600)
  and (W[6] > 700)
  and (W[7] > 800)
  and (W[8] > 900)
  and (W[9] > 1000)
  and (W[10] > 1100)
  then
    Result:= True;
end;

end.
