unit split_tail_comment;

interface

procedure Go;

implementation

procedure Go;
var
  A, B: Integer; { shared counters }
  C, D: Integer; (* paren-star tail *)
  E, F: Integer; // line tail
begin
  A := 0; B := A; C := B; D := C; E := D; F := E;
end;

end.
