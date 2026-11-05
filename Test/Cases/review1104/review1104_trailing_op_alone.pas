unit review1104_trailing_op_alone;
// REVIEW-2026-11-04-corruption L6: a line that fits but ends in a binary
// operator, with no other depth-0 operator before it (`Z := 1 shl`,
// `Z := -`), followed by an over-long continuation. The trailing operator
// was left behind and the continuation stayed over-long; it now leads the
// continuation, which is then broken like any other (a lone parenthesised
// group stays one atom, as BreakComponents documents).

interface

function F(A: Integer): Integer;
function Go: Integer;

implementation

function F(A: Integer): Integer;
begin
  Result := A;
end;

function Go: Integer;
var
  Z: Integer;
begin
  Z := 1 shl
    (F(1) + F(2) + F(3) + F(4) + F(5) + F(6) + F(7) + F(8) + F(9) + F(10) + F(11) + F(12) + F(13) + F(14) + F(15) + F(16) + F(17) + F(18) + F(19) + F(20) + F(21) + F(22) + F(23) + F(24)) mod 7;
  Z := -
    (F(1) + F(2) + F(3) + F(4) + F(5) + F(6) + F(7) + F(8) + F(9) + F(10) + F(11) + F(12) + F(13) + F(14) + F(15) + F(16) + F(17) + F(18) + F(19) + F(20) + F(21) + F(22) + F(23) + F(24) + F(25));
  Z := Z -
    F(1) - F(2) - F(3) - F(4) - F(5) - F(6) - F(7) - F(8) - F(9) - F(10) - F(11) - F(12) - F(13) - F(14) - F(15) - F(16) - F(17) - F(18) - F(19) - F(20) - F(21) - F(22) - F(23) - F(24);
  Result := Z;
end;

end.
