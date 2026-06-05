unit d10_nested;

interface

implementation

procedure Outer;

  procedure Inner;
  begin
    var K: Integer := 7;
    WriteLn(K);
  end;

begin
  Inner;
end;

end.
