unit inline_brace_comment;

interface

implementation

procedure P;
var
  A, B, C, D: Integer;
begin
  A := B {+C} + D;
  A := B (*+C*) + D;
  A := B {comment with spaces} + D;
end;

end.
