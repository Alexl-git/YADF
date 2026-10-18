unit break_case_types;

interface

type
  TRng = 0..3;

var
  C, D: (Red, Green);
  A, B: array[Low(TRng)..High(TRng)] of Integer;

procedure Demo(K: Integer; var Flag: Boolean);

implementation

procedure Demo(K: Integer; var Flag: Boolean);
begin
  case K of
    0, 1: Flag:= True;
    2, 3: Inc(K);
  end;
end;

end.
