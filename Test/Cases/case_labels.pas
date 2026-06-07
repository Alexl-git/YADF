unit case_labels;

interface

implementation

procedure Demo(K: Integer; var Flag: Boolean);
var
  A, B, C: Integer;
begin
  A:= 0; B:= 0; C:= 0;
  case K of
    0, 1, 2: Flag:= True;
    3, 4: DoThing(K);
    5, 6, 7: begin Flag:= False; Inc(A); end;
  else
    Inc(B);
  end;
end;

end.
