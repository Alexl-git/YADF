unit broken_unit;

interface

implementation

procedure A;
var
  I: Integer;
begin
  for I := 0 to 10 do
  begin
    if I = 5 then
      Continue;
    Writeln(I);
  // TODO -oYADF : missing 'end;' for the for-begin block opened above

procedure B;
begin
  Writeln('B is parseable as tokens even though A above is broken');
  // TODO -oYADF : missing 'end;' for procedure B's begin

end.
