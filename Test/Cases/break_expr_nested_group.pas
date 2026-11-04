program break_expr_nested_group;

// Review 2026-11-03 A-L4: an author's break inside a nested call group, formatted at
// --indent 8 --max-len 60, split `+ F(F(111)` / `+ F(112));` on pass 1 and joined it
// on pass 2. One format must reach the fixed point.

function F(A: Integer): Integer;
begin
  Result := A;
end;

var
  Z: Integer;

begin
  Z := F(F(101) + F(102)) + F(F(103) + F(104)) + F(F(105) + F(106)) + F(F(107) +
    F(108)) + F(F(109) + F(110)) + F(F(111) + F(112));
  Writeln(Z);
end.