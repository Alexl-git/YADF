unit collapse_blocks;

interface

implementation

procedure Demo(X: Integer);
var
  A, B: Integer;
  S: string;
begin
  if X > 0 then
  begin
    A := 1;
    B := 2;
  end;
  for A := 0 to 9 do
  begin
    Inc(B);
    Inc(X);
  end;
  while X > 0 do
  begin
    Dec(X);
  end;
  if X = 5 then
  begin
    A := 1;
  end
  else
  begin
    B := 2;
  end;
  // nested: outer stays expanded, inner leaf collapses
  while X > 0 do
  begin
    if A > 0 then
    begin
      Dec(X);
    end;
  end;
  // comment inside the body keeps the block expanded
  if B > 0 then
  begin
    A := 1; // keep me
    B := 2;
  end;
  // string interior spaces must survive the space-squeeze of a collapse
  if A > 0 then
  begin
    S := 'a   b';
  end;
end;

end.
