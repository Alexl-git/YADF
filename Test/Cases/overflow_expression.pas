unit overflow_expression;

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
  Z := F(11) + F(12) + F(13) + F(14) + F(15) + F(16) + F(17) + F(18) + F(19) + F(20) + F(21) + F(22) + F(23) + F(24) + F(25) + F(26) + F(27) + F(28) + F(29) + F(30) + F(31) + F(32) + F(33);
  Z := F(F(101) + F(102)) + F(F(103) + F(104)) + F(F(105) + F(106)) + F(F(107) + F(108)) + F(F(109) + F(110)) + F(F(111) + F(112)) + F(F(113) + F(114)) + F(F(115) + F(116));
  Z := 1 + 2 + 3;
end;

end.
