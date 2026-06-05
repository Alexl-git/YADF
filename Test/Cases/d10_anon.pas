unit d10_anon;

interface

uses
  System.SysUtils;

implementation

procedure Demo;
var
  P: TProc;
begin
  P := procedure
  begin
    var Z: Integer := 3;
    WriteLn(Z);
  end;
  P();
end;

end.
