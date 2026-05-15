unit anon_proc_indent;

// Regression: inline anonymous procedure/function expressions used as
// arguments (e.g. CallSomething(procedure(X) begin ... end)) were
// pushing a phantom "pending procedure body" entry in ReindentByDepth,
// because the ptProcedure/ptFunction handler fired unconditionally
// outside class/record contexts. The inner balanced begin/end never
// consumed that marker, leaving OpenProcRegions elevated and adding a
// +1 indent bonus to every line after the call. Symptom: line after
// the anon proc got 4 spaces instead of 2, and the cascade pushed all
// subsequent lines (including the procedure's own `end;`) one level
// too deep. Fix added a `ParensDepth = 0` guard so the handler only
// fires for real top-level method declarations, not anonymous-method
// expressions nested inside argument parens. (Bug found while
// formatting Blueprint4.pas, 2026-05-15.)
//
// This file must format-idempotently: every line below is already at
// the depth ReindentByDepth should produce, so YADF.exe --stdout
// against this file must emit byte-identical output.

interface

implementation

procedure Outer;
begin
  CallSomething(procedure(X: Integer) begin DoFoo(X); end);
  NextLine   := 42;
  AnotherLine:= 7 ;
  CallAgain(function(Y: Integer): Boolean begin Result:= Y > 0; end);
  AfterTheFunc:= True;
end;

procedure Sibling;
begin
  DoStuff;
end;

end.
