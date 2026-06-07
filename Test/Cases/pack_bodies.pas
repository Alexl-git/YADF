unit pack_bodies;

interface

implementation

procedure P(N: Integer; X, Y: Boolean);
begin
  for I := 0 to N do
    Inc(N);
  if X then
    DoIt;
  while Y do
    Step;
  for I := 0 to N do
    if Odd(I) then
      DoOdd(I);
end;

procedure Q(K: Integer; Flag: Boolean);
begin
  case K of
    0:
      DoZero;
    1:
      if Flag then
        DoOne;
  else
    DoDefault;
  end;
end;

end.
