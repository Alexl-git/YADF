unit idem_anon_assign_wrap;

// Owner decision (2026-11-03): when an assignment and an anonymous method's
// procedure / unction header land on two lines, the header goes one Indent
// in as a continuation; begin/end follow that header line, the body one more in.

interface

implementation

uses
  System.SysUtils;

procedure Wrapped(AFlag: Boolean);
var
  P: TProc;
  F: TFunc<Integer>;
  G: TFunc<Integer, Integer>;
begin
  P :=
  procedure
  begin
    Writeln('a');
  end;
  F :=
      function: Integer
      begin
        Result := 1;
      end;
  G :=
    function(A: Integer): Integer
    begin
      if A > 0 then
        Result := A
      else
        Result := 0;
    end;
  if AFlag then
    P :=
    procedure
    begin
      Writeln('b');
    end;
  P := procedure
  begin
    Writeln('c');
  end;
  Writeln('after');
end;

end.