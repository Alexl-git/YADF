unit anon_proc_split;

{ Companion to anon_array_split: anonymous PROCEDURAL types (procedure / function)
  are also distinct-per-declaration and must NOT be split. EXCLUDED from the
  byte-golden harness (test_golden_format.ps1 $exclude) because a separate,
  pre-existing indent quirk over-indents begin/end when a var block holds a
  leading procedure/function type (the of-object / procedural-indent cluster).
  This fixture asserts only the no-split property via regex in
  test_format_regressions.ps1. }

interface

implementation

procedure AnonProcs;
var
  ProcA, ProcB: procedure of object;
  FuncA, FuncB: function: Integer;
  NamedA, NamedB: Integer;
begin
  ProcA := nil;
  ProcB := nil;
  FuncA := nil;
  FuncB := nil;
  NamedA := 0;
  NamedB := 0;
end;

end.
