unit UnaryCondAlign;

interface

function Probe(A, B: Integer): Integer;

implementation

function Probe(A, B: Integer): Integer;
var
  Alpha: Integer;
  Be: Integer;
  Gamma: Integer;
  Ok: Boolean;
begin
  Alpha:= -1;
  Be:= 22;
  Gamma:= +3;
  Result:= Alpha + Be + Gamma;
  if A = 1 then Exit(0);
  if Alpha = 1 then Exit(1);
  while A = 1 do Exit(2);
  while Alpha = 1 do Exit(3);
  if (A > 0) and (B = 2) then Exit(4);
  if (Alpha > 0) and (B = 2) then Exit(5);
  Ok:= (A > 0)
    and (B = 2)
    or (Alpha = 3);
  Result:= Alpha
    - Be
    + Gamma;
end;

end.
