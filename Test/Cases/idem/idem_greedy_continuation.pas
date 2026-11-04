unit idem_greedy_continuation;

// Greedy breaker (BreakLongExpressions OFF) at Indent 4 / MaxLen 60: a call group
// left open at a continuation line's end was re-joined by the next format's walker
// and re-broken one Indent deeper than the line it continued.

interface

implementation

function F(X: Integer): Integer;
begin
  Result := X * 2;
end;

procedure P;
var
  Z: Integer;
begin
  Z := F(F(101) + F(102)) + F(F(103) + F(104)) + F(F(105) + F(106)) + F(F(107) + F(108)) + F(F(109) + F(110)) + F(F(111) + F(112)) + F(F(113) + F(114)) + F(F(115) + F(116));
  if Z > 0 then
    Z := F(F(201) + F(202)) + F(F(203) + F(204)) + F(F(205) + F(206)) + F(F(207) + F(208)) + F(F(209) + F(210));
end;

end.