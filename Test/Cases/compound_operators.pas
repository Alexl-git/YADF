unit compound_operators;

// Regression: BUG_LE_OPERATOR.md (2026-05-14).
// The const-equals alignment pass was treating the trailing `=` of
// `<=` and `>=` as a candidate const-block anchor and right-padding
// it, producing dcc-invalid output like `>          = N`. The fix
// extends the skip guard in FindAnchorAtTopLevel to also skip `=`
// when preceded by `<` or `>` (in addition to the existing `:=`
// case). This file must round-trip byte-for-byte under --check.

interface

implementation

procedure Demo(AID: Integer; const A, B, I, N, X, Y: Integer);
begin
  if Length(AID) <= 0 then Exit;
  if I >= N then Break;
  if A <> B then DoSomething;
  X:= Y + 1;
end;

end.
