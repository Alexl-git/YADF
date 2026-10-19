program d10_loop_reinit;
{$APPTYPE CONSOLE}
procedure Loops;
var
  N: Integer;
begin
  for var I := 1 to 3 do
  begin
    var S: string;
    if I = 2 then
      S := 'x';
    Write('[', S, ']');
  end;
  Writeln;
  N := 0;
  while N < 3 do
  begin
    Inc(N);
    var A, B: string;
    if N = 2 then
    begin
      A := 'a';
      B := 'b';
    end;
    Write('[', A, B, ']');
  end;
  Writeln;
  N := 0;
  repeat
    Inc(N);
    var T: string;
    if N = 2 then
      T := 't';
    Write('[', T, ']');
  until N = 3;
  Writeln;
  // single-statement loop bodies (no begin of their own): the declaration sits in a
  // nested block that is still re-entered on every iteration.
  for var K := 1 to 3 do
    if K > 0 then
    begin
      var V: string;
      if K = 2 then
        V := 'v';
      Write('[', V, ']');
    end;
  Writeln;
  N := 0;
  while N < 3 do
    if N < 0 then
      Inc(N)
    else
    begin
      Inc(N);
      var W: string;
      if N = 2 then
        W := 'w';
      Write('[', W, ']');
    end;
  Writeln;
end;
procedure Straight;
begin
  var U: string;
  U := U + 'u';
  Writeln(U);
end;
begin
  Loops;
  Straight;
end.