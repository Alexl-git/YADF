unit review_d10_ifdef;

// Regression fixture (review 2026-10-14, reviewer 4): --d10 hoisted an inline
// var declared inside {$IFDEF} to the routine's top var block, OUTSIDE the
// conditional. When the type only exists under the symbol, the output no
// longer compiled with the symbol undefined. A conditional inline var / const
// / for-var is now left in place with a TODO instead.

interface

procedure P;

implementation

procedure P;
begin
  {$IFDEF YADF_TEST_NEVER_DEFINED}
  var X: TOnlyWhenDefined := nil;
  const C = SizeOf(TOnlyWhenDefined);
  {$ENDIF}
end;

end.
