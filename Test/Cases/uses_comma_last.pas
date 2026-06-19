unit uses_comma_last;

{ UsesCommaLast controls the BROKEN (multi-line) uses layout. Default false ->
  comma-first (the diff-friendly style, ";" on its own line). True -> comma-last
  (trailing comma per unit, ";" on the last unit's line). The inline single-line
  form (UsesAlwaysBreak=false, short clause) is unaffected. The golden harness
  formats this with defaults (comma-first); the comma-last form is asserted by
  test_uses_comma_last.ps1. }

interface

uses
  System.SysUtils, System.StrUtils, System.Classes;

implementation

end.
