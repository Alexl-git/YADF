unit idem_trailing_operator;

// Task 10 mechanism B: an over-long line whose only top-level boundary is a
// TRAILING operator was broken there, leaving the operator alone on its own
// line; the next format joined it to the following line.

interface

function Check(const AName, AUnit: string; AValue: Int64; AState: Integer): Boolean;

implementation

uses
  System.SysUtils;

function Check(const AName, AUnit: string; AValue: Int64; AState: Integer): Boolean;
begin
  Result:= False;
  if (AState = 2) and (AValue > 0) and
    ((Length(AName) > 3) or (Pos('ABC', UpperCase(AName)) > 0) or (Pos('DEF', UpperCase(AName)) > 0) or (Pos('GHI', UpperCase(AName)) > 0) or (Length(AUnit) > 4) or (AValue > 100)) and
    (AState <> 3) then
    Result:= True;
end;

end.
