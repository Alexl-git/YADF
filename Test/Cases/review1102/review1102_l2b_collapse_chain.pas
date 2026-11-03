unit review1102_l2b_collapse_chain;
// REVIEW-2026-11-02 corruption L2b (--pack-statements --collapse-blocks): the
// second block of an if .. else if chain was folded only by the next format.
interface
procedure P(X: Integer);
implementation
procedure P(X: Integer);
var
  A: Integer;
begin
  if X > 0 then begin A := 13; end else if X < 0 then begin A := 14; end else A := 15;
  Writeln(A);
end;
end.